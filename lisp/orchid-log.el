;;; orchid-log.el --- Log file monitoring for Orchid -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Monitor orchid conversation.jsonl files and stream updates into chat buffers
;; in real-time using auto-revert-tail-mode.  Supports extensible log parsing.

;;; Code:

(require 'autorevert)
(require 'core/orchid-core)
(require 'log/orchid-logging)
(require 'log/orchid-log-registry)
(require 'log/orchid-log-restore)
(require 'log/orchid-log-parse)
(require 'log/orchid-log-monitor)

(defvar-local orchid-log--poll-timer nil
  "Timer used to poll the session event file.")


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
  "Return the simplified-harness event stream for SESSION-ID."
  (orchid-core-session-conversation-path session-id))

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
      ;; The monitor owns file reads; visiting the file would enable global
      ;; auto-revert and cause competing reloads.
      (set-buffer-modified-p nil)
      (rename-buffer buffer-name t)
      (goto-char (point-max))
      (current-buffer))))

(defun orchid-log--process-new-content (session-id)
  "Process complete lines in the monitor buffer for SESSION-ID.
The registry's seen-event table makes a full rescan safe."
  (when-let ((entry (orchid-log--get-entry session-id)))
    (let ((buffer (plist-get entry :buffer))
          (callback (plist-get entry :callback)))
      (with-current-buffer buffer
        (goto-char (point-min))
        (let ((lines-processed 0))
          (while (< (point) (point-max))
            (let ((line-end (line-end-position)))
              (when (< line-end (point-max))
                (let* ((line (buffer-substring-no-properties
                              (line-beginning-position) line-end))
                       (result (orchid-log--parse-line-with-id line))
                       (event-id (and result (plist-get result :event-id)))
                       (is-duplicate (and event-id
                                          (orchid-log--event-seen-p session-id event-id))))
                  (unless is-duplicate
                    (when-let* ((parsed (and result (plist-get result :parsed)))
                                (display-text (plist-get parsed :display)))
                      (when (and callback (not (string-empty-p display-text)))
                        (when event-id
                          (orchid-log--mark-event-seen session-id event-id))
                        (setq lines-processed (1+ lines-processed))
                        (funcall callback parsed)))))))
            (forward-line 1))
          (orchid-log "Session %s: processed %d new lines"
                      session-id lines-processed))))))

(defun orchid-log--poll (session-id buffer)
  "Read the event file and process complete lines for SESSION-ID.
This deliberately avoids `revert-buffer' and auto-revert."
  (when (and (buffer-live-p buffer)
             (orchid-log-monitoring-p session-id))
    (condition-case err
        (with-current-buffer buffer
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert-file-contents (orchid-log--conversation-file session-id)))
          (orchid-log--process-new-content session-id))
      (error
       (orchid-log "Failed to poll log for %s: %s"
                   session-id (error-message-string err))))))

(defun orchid-log-start-monitoring (session-id callback &optional seen-events)
  "Start monitoring SESSION-ID and call CALLBACK for new events.
SEEN-EVENTS contains IDs already rendered during history restoration."
  (when (orchid-log-monitoring-p session-id)
    (error "Already monitoring session %s" session-id))
  (let* ((log-file (orchid-log--find-file session-id))
         (buffer (orchid-log--create-buffer session-id log-file)))
    (with-current-buffer buffer
      (when (fboundp 'auto-revert-tail-mode)
        (auto-revert-tail-mode -1))
      (when (fboundp 'auto-revert-mode)
        (auto-revert-mode -1)))
    (orchid-log--register session-id log-file buffer callback seen-events)
    (with-current-buffer buffer
      (setq-local orchid-log--poll-timer
                    (run-at-time orchid-log-auto-revert-interval
                                 orchid-log-auto-revert-interval
                                 #'orchid-log--poll
                                 session-id buffer)))
    buffer))

(defun orchid-log-stop-monitoring (session-id)
  "Stop monitoring and kill log buffer for SESSION-ID."
  (when-let ((entry (orchid-log--get-entry session-id)))
    (let ((buffer (plist-get entry :buffer)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (when (timerp orchid-log--poll-timer)
            (cancel-timer orchid-log--poll-timer)
            (setq orchid-log--poll-timer nil)))
        (kill-buffer buffer)))
    (orchid-log--remove-entry session-id)))

(defun orchid-log-monitoring-p (session-id)
  "Check if currently monitoring SESSION-ID."
  (not (null (orchid-log--get-entry session-id))))

(defun orchid-log-get-buffer (session-id)
  "Get log buffer for SESSION-ID, or nil if not monitoring."
  (when-let ((entry (orchid-log--get-entry session-id)))
    (plist-get entry :buffer)))

(defun orchid-log-flush (session-id)
  "Read and process all currently written events for SESSION-ID."
  (when-let ((buffer (orchid-log-get-buffer session-id)))
    (orchid-log--poll session-id buffer)))
(defun orchid-log-show (session-id)
  "Display log buffer for SESSION-ID in a window."
  (interactive "sSession ID: ")
  (if-let ((buffer (orchid-log-get-buffer session-id)))
      (display-buffer buffer)
    (error "Not monitoring session %s" session-id)))

(provide 'orchid-log)

;;; orchid-log.el ends here
