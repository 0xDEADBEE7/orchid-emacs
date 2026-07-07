;;; orchid-log-restore.el --- Session history restore for Orchid log -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Restores conversation history from JSONL log files.
;; Extracted from orchid-log.el to keep individual files under 200 lines.

;;; Code:

(require 'core/orchid-faces)
(require 'orchid-parsers)
(require 'log/orchid-logging)

;; Forward declarations
(declare-function orchid-log--find-file "orchid-log")
(declare-function orchid-log--parse-line-with-id "orchid-log")
(defvar orchid-log-restore-max-size-mb)
(defvar orchid-log-restore-max-events)
(defvar orchid-log--restore-mode)

(defun orchid-log-restore--scan-backward (max-events seen-events)
  "Scan backward from point-max collecting up to MAX-EVENTS unique events.
Returns events in chronological order (oldest first).
Scanning backward with push naturally produces oldest-first order."
  (let ((events '())
        (line-count 0)
        (parse-start (current-time)))
    (goto-char (point-max))
    (while (and (not (bobp)) (< (length events) max-events))
      (forward-line -1)
      (setq line-count (1+ line-count))
      (let ((line (buffer-substring-no-properties
                   (line-beginning-position)
                   (line-end-position))))
        (when-let ((result (orchid-log--parse-line-with-id line)))
          (let* ((event-id (plist-get result :event-id))
                 (parsed (plist-get result :parsed))
                 (is-duplicate (and event-id (gethash event-id seen-events))))
            (unless is-duplicate
              (let ((display-text (plist-get parsed :display)))
                (when (and display-text (not (string-empty-p display-text)))
                  (when event-id (puthash event-id t seen-events))
                  (push (cons line parsed) events))))))))
    (orchid-log "PERF: Parsed %d lines (backward) into %d events in %.3fs"
                line-count (length events)
                (float-time (time-subtract (current-time) parse-start)))
    events))

(defun orchid-log-restore--scan-forward (seen-events)
  "Scan forward from point-min collecting all unique events.
Returns events in chronological order."
  (let ((events '())
        (line-count 0)
        (parse-start (current-time)))
    (goto-char (point-min))
    (while (not (eobp))
      (setq line-count (1+ line-count))
      (let ((line (buffer-substring-no-properties
                   (line-beginning-position)
                   (line-end-position))))
        (when-let ((result (orchid-log--parse-line-with-id line)))
          (let* ((event-id (plist-get result :event-id))
                 (parsed (plist-get result :parsed))
                 (is-duplicate (and event-id (gethash event-id seen-events))))
            (unless is-duplicate
              (let ((display-text (plist-get parsed :display)))
                (when (and display-text (not (string-empty-p display-text)))
                  (when event-id (puthash event-id t seen-events))
                  (push (cons line parsed) events))))))
        (forward-line 1)))
    (orchid-log "PERF: Parsed %d lines (forward) into %d events in %.3fs"
                line-count (length events)
                (float-time (time-subtract (current-time) parse-start)))
    (nreverse events)))

(defun orchid-log-restore-session (session-id callback &optional seen-events-table max-events-override)
  "Restore conversation history from JSONL log for SESSION-ID.
CALLBACK is called for each event in chronological order.
SEEN-EVENTS-TABLE is an optional hash-table of already-seen event IDs.
MAX-EVENTS-OVERRIDE overrides `orchid-log-restore-max-events' when non-nil.
Returns a plist with :count and :seen-events."
  (let* ((start-time (current-time))
         (log-file (orchid-log--find-file session-id))
         (seen-events (or seen-events-table (make-hash-table :test 'equal)))
         (orchid-log--restore-mode t)
         (events '())
         (max-events (or max-events-override orchid-log-restore-max-events))
         (max-bytes (when orchid-log-restore-max-size-mb
                      (truncate (* orchid-log-restore-max-size-mb 1024 1024))))
         (file-size (when max-bytes (nth 7 (file-attributes log-file))))
         (start-position (when (and max-bytes file-size (> file-size max-bytes))
                           (- file-size max-bytes))))

    (let ((file-read-start (current-time)))
      (with-temp-buffer
        (if start-position
            (progn
              (insert-file-contents log-file nil start-position nil)
              (goto-char (point-min))
              (when (not (bolp))
                (forward-line 1)))
          (insert-file-contents log-file))
        (orchid-log "PERF: File read in %.3fs (size: %s bytes)"
                    (float-time (time-subtract (current-time) file-read-start))
                    (buffer-size))
        (setq events
              (if max-events
                  (orchid-log-restore--scan-backward max-events seen-events)
                (orchid-log-restore--scan-forward seen-events)))))

    (let ((callback-start (current-time))
          (prev-event-type nil))
      (dolist (event events)
        (let* ((parsed (cdr event))
               (event-type (plist-get parsed :event-type)))
          (when (and (equal event-type "user") prev-event-type)
            (funcall callback
                     (list :display (propertize (concat "\n" (make-string 80 ?─) "\n\n")
                                                'face 'orchid-chat-separator-face)
                           :event-type "separator")))
          (funcall callback parsed)
          (setq prev-event-type event-type)))
      (orchid-log "PERF: Processed %d events in %.3fs"
                  (length events)
                  (float-time (time-subtract (current-time) callback-start))))

    (orchid-log "PERF: Total restore time: %.3fs"
                (float-time (time-subtract (current-time) start-time)))
    (list :count (length events)
          :seen-events seen-events)))

(provide 'log/orchid-log-restore)

;;; orchid-log-restore.el ends here
