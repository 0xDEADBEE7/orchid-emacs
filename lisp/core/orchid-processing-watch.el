;;; orchid-processing-watch.el --- File-notify watch for processing indicator -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; File-notify watch logic for the Orchid processing indicator, extracted from
;; orchid-processing-indicator.el to keep that module within the 200-line target.

;;; Code:

(require 'filenotify)
(require 'session/orchid-session)
(require 'log/orchid-logging)

;; Buffer-local variables defined in orchid-processing-indicator.el
(defvar orchid-processing--marker)
(defvar orchid-processing--session-id)
(defvar orchid-processing--finished)
(defvar orchid-processing--seen-running)
(defvar orchid-processing--watch)
(defvar orchid-processing--status-message)

;; Functions defined in orchid-processing-indicator.el
(declare-function orchid-processing--read-status "orchid-processing-indicator" (session-id))
(declare-function orchid-processing--read-metadata "orchid-processing-indicator" (session-id))
(declare-function orchid-processing--elapsed-seconds "orchid-processing-indicator" ())
(declare-function orchid-processing--update-display "orchid-processing-indicator" ())
(declare-function orchid-processing-stop "orchid-processing-indicator" ())
(declare-function orchid-processing-update-token-estimate "orchid-processing-indicator" (estimate))
(declare-function orchid-processing--refresh-chunk-count "orchid-processing-indicator" ())

(defun orchid-processing--on-metadata-change (_event)
  "Handle metadata.json change event.
Called by file-notify when metadata.json is written."
  (when (and orchid-processing--marker
             (marker-buffer orchid-processing--marker)
             (not orchid-processing--finished))
    (let* ((metadata (orchid-processing--read-metadata orchid-processing--session-id))
           (status  (plist-get metadata :status))
           (running (equal status "running"))
           (tokens  (plist-get metadata :token_estimate)))
      (when (integerp tokens)
        (orchid-processing-update-token-estimate tokens))
      (when running
        (setq orchid-processing--seen-running t))
      (orchid-session-notify-status-change orchid-processing--session-id running)
      (when (and orchid-processing--seen-running (not running))
        (orchid-log "Process finished after %ds" (orchid-processing--elapsed-seconds))
        (setq orchid-processing--finished t)
        (setq orchid-processing--status-message nil)
        (orchid-processing--update-display)
        (orchid-processing-stop)))))

(defun orchid-processing--attach-metadata-watch (metadata-path buf session-id attempt)
  "Attach file-notify watch on the session directory for BUF and SESSION-ID.
METADATA-PATH is the full path to metadata.json.
Watches the directory rather than the file so kqueue doesn't lose the watch
when orchid rewrites metadata.json via atomic rename.
If the directory does not exist yet, retry up to 20 times at 1s intervals."
  (let ((session-dir (file-name-directory metadata-path)))
    (cond
     ((file-exists-p session-dir)
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (setq orchid-processing--watch
                (file-notify-add-watch
                 session-dir
                 '(change)
                 (lambda (event)
                   (let ((f2 (file-name-nondirectory (or (nth 2 event) "")))
                         (f3 (file-name-nondirectory (or (nth 3 event) ""))))
                     (when (buffer-live-p buf)
                       (cond
                        ((or (string-equal "metadata.json" f2)
                             (string-equal "metadata.json" f3))
                         (with-current-buffer buf
                           (orchid-processing--on-metadata-change event)))
                        ((or (string-equal "stream.state" f2)
                             (string-equal "stream.state" f3))
                         (with-current-buffer buf
                           (orchid-processing--refresh-chunk-count)
                           (orchid-processing--update-display))))))))))))
     ((< attempt 20)
      (run-with-timer
       1 nil
       (lambda ()
         (orchid-processing--attach-metadata-watch
          metadata-path buf session-id (1+ attempt)))))
     (t
      (orchid-log "Session dir never appeared for session %s after 20s" session-id)))))

(provide 'core/orchid-processing-watch)

;;; orchid-processing-watch.el ends here
