;;; orchid-log.el --- Log file monitoring for Orchid -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Monitor orchid conversation.jsonl files and stream updates into chat buffers
;; in real-time using auto-revert-tail-mode.  Supports extensible log parsing.

;;; Code:

(require 'autorevert)
(require 'log/orchid-logging)
(require 'log/orchid-log-registry)
(require 'log/orchid-log-restore)
(require 'log/orchid-log-parse)
(require 'log/orchid-log-monitor)

;;; Customization

(defgroup orchid-log nil
  "Log monitoring for Orchid."
  :group 'orchid
  :prefix "orchid-log-")

(defcustom orchid-log-auto-revert-interval 0.5
  "How often to check for log updates in seconds."
  :type 'number
  :group 'orchid-log)

(defcustom orchid-log-show-raw-logs nil
  "If non-nil, show raw log buffers for debugging."
  :type 'boolean
  :group 'orchid-log)

(defcustom orchid-log-restore-max-size-mb 5.0
  "Maximum size in MB to restore from log files.
Set to nil to restore entire log file (may be slow for large files)."
  :type '(choice (number :tag "Max size in MB")
                 (const :tag "Restore entire file" nil))
  :group 'orchid-log)

(defcustom orchid-log-restore-max-events 250
  "Maximum number of events to restore from log files.
Set to nil to restore all events."
  :type '(choice (integer :tag "Max number of events")
                 (const :tag "Restore all events" nil))
  :group 'orchid-log)

;;; Private Variables

(defvar orchid-log--restore-mode nil
  "If non-nil, parsers are in restore mode.
In restore mode, user text messages are displayed (normally filtered).")

(defvar orchid-log--event-deduplication t
  "If non-nil, skip events whose IDs have already been processed.")

;;; Private Functions

(defun orchid-log--conversation-file (session-id)
  "Return path to conversation.jsonl for SESSION-ID."
  (expand-file-name
   (format "~/.config/orchid/conversations/%s/conversation.jsonl" session-id)))

(defun orchid-log--find-file (session-id)
  "Return conversation log path for SESSION-ID, erroring if not found."
  (let ((path (orchid-log--conversation-file session-id)))
    (unless (file-exists-p path)
      (error "Log file not found for session '%s': %s" session-id path))
    path))

(defun orchid-log--create-buffer (session-id log-file)
  "Create log buffer for SESSION-ID watching LOG-FILE.
Only loads the last N MB (based on orchid-log-restore-max-size-mb)."
  (let* ((buffer-name (format " *orchid-log:%s*" session-id))
         (max-bytes (when orchid-log-restore-max-size-mb
                      (truncate (* orchid-log-restore-max-size-mb 1024 1024))))
         (file-size (when max-bytes (nth 7 (file-attributes log-file))))
         (start-position (when (and max-bytes file-size (> file-size max-bytes))
                           (- file-size max-bytes)))
         (buffer (generate-new-buffer buffer-name)))
    (with-current-buffer buffer
      (if start-position
          (progn
            (insert-file-contents log-file nil start-position nil)
            (goto-char (point-min))
            (when (not (bolp))
              (forward-line 1)
              (delete-region (point-min) (point))))
        (insert-file-contents log-file))
      (set-visited-file-name log-file t t)
      (set-buffer-modified-p nil)
      (rename-buffer buffer-name t)
      (goto-char (point-max))
      (current-buffer))))

(defun orchid-log--process-new-content (session-id)
  "Process new content in log buffer for SESSION-ID."
  (let ((entry (orchid-log--get-entry session-id)))
    (when entry
      (let* ((buffer (plist-get entry :buffer))
             (last-pos (or (plist-get entry :last-position) 1))
             (callback (plist-get entry :callback)))
        (with-current-buffer buffer
          (let ((buffer-size (point-max)))
            (orchid-log "Processing session %s: last-pos=%d buffer-size=%d"
                     session-id last-pos buffer-size)
            (when (> last-pos buffer-size)
              (orchid-log "WARNING: last-pos (%d) > buffer-size (%d), resetting"
                       last-pos buffer-size)
              (setq last-pos 1))
            (goto-char last-pos)
            (let ((lines-processed 0))
              (while (not (eobp))
                (let* ((line (buffer-substring-no-properties
                             (line-beginning-position)
                             (line-end-position)))
                       (result (orchid-log--parse-line-with-id line))
                       (event-type (when result (plist-get result :type)))
                       (event-id (when (and result orchid-log--event-deduplication)
                                   (plist-get result :event-id)))
                       (is-duplicate (when event-id
                                       (orchid-log--event-seen-p session-id event-id))))
                  (cond
                   (is-duplicate
                    (orchid-log "Skipping duplicate event: %s" event-id))
                   ((and result callback)
                    (let* ((parsed (plist-get result :parsed))
                           (display-text (plist-get parsed :display))
                           (has-content (and display-text (not (string-empty-p display-text)))))
                      (when has-content
                        (when event-id
                          (orchid-log "Marking event as seen: %s" event-id)
                          (orchid-log--mark-event-seen session-id event-id))
                        (setq lines-processed (1+ lines-processed))
                        (let* ((display-len (length display-text))
                               (preview (substring display-text 0 (min 100 display-len))))
                          (orchid-log "Event #%d: type=%s id=%s len=%d preview=%S"
                                   lines-processed event-type (or event-id "NO-ID") display-len preview))
                        (funcall callback parsed)))))
                  (forward-line 1)))
              (orchid-log "Session %s: processed %d lines, new-pos=%d"
                       session-id lines-processed (point))
              (orchid-log--set-last-position session-id (point)))))))))

;;; Public API

(defun orchid-log-start-monitoring (session-id callback)
  "Start monitoring log file for SESSION-ID.
CALLBACK is called with each new parsed event.
Returns the log buffer."
  (when (orchid-log-monitoring-p session-id)
    (error "Already monitoring session %s" session-id))
  (let* ((log-file (orchid-log--find-file session-id))
         (buffer (orchid-log--create-buffer session-id log-file)))
    (with-current-buffer buffer
      (auto-revert-tail-mode 1)
      (setq-local auto-revert-interval orchid-log-auto-revert-interval)
      (setq-local auto-revert-verbose nil)
      (add-hook 'after-revert-hook
                (lambda () (orchid-log--process-new-content session-id))
                nil t))
    (orchid-log--register session-id log-file buffer callback)
    buffer))

(defun orchid-log-stop-monitoring (session-id)
  "Stop monitoring and kill log buffer for SESSION-ID."
  (when-let ((entry (orchid-log--get-entry session-id)))
    (let ((buffer (plist-get entry :buffer)))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))
    (orchid-log--remove-entry session-id)))

(defun orchid-log-monitoring-p (session-id)
  "Check if currently monitoring SESSION-ID."
  (not (null (orchid-log--get-entry session-id))))

(defun orchid-log-get-buffer (session-id)
  "Get log buffer for SESSION-ID, or nil if not monitoring."
  (when-let ((entry (orchid-log--get-entry session-id)))
    (plist-get entry :buffer)))

(defun orchid-log-show (session-id)
  "Display log buffer for SESSION-ID in a window."
  (interactive "sSession ID: ")
  (if-let ((buffer (orchid-log-get-buffer session-id)))
      (display-buffer buffer)
    (error "Not monitoring session %s" session-id)))

(provide 'orchid-log)

;;; orchid-log.el ends here
