;;; orchid-log-registry.el --- Session registry for log monitoring -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Manages the registry of active log monitoring sessions.
;; Tracks position and event deduplication for each session.

;;; Code:

(require 'json)
(require 'log/orchid-logging)

(defvar orchid-log--registry nil
  "List of monitoring entries.
Each entry is a plist with :session-id, :log-file, :buffer,
:callback, :last-position, and :seen-events.")

(defun orchid-log--register (session-id log-file buffer callback)
  "Register monitoring entry for SESSION-ID watching LOG-FILE.
BUFFER is the log buffer.  CALLBACK is called with each parsed event."
  (let ((initial-pos (with-current-buffer buffer (point))))
    (orchid-log "Registering session %s with initial position %d (buffer size: %d)"
             session-id initial-pos (with-current-buffer buffer (point-max)))
    (push (list :session-id session-id
                :log-file log-file
                :buffer buffer
                :callback callback
                :last-position initial-pos
                :seen-events (make-hash-table :test 'equal))
          orchid-log--registry)))

(defun orchid-log--get-entry (session-id)
  "Get monitoring entry for SESSION-ID."
  (cl-find session-id orchid-log--registry
           :key (lambda (e) (plist-get e :session-id))
           :test #'equal))

(defun orchid-log--remove-entry (session-id)
  "Remove monitoring entry for SESSION-ID."
  (setq orchid-log--registry
        (cl-remove session-id orchid-log--registry
                   :key (lambda (e) (plist-get e :session-id))
                   :test #'equal)))

(defun orchid-log--set-last-position (session-id pos)
  "Update last processed position for SESSION-ID to POS."
  (when-let ((entry (orchid-log--get-entry session-id)))
    (orchid-log "Updating session %s position: %d -> %d"
             session-id (plist-get entry :last-position) pos)
    (plist-put entry :last-position pos)))

(defun orchid-log--event-seen-p (session-id event-id)
  "Check if EVENT-ID has been seen for SESSION-ID."
  (when event-id
    (when-let ((entry (orchid-log--get-entry session-id)))
      (gethash event-id (plist-get entry :seen-events)))))

(defun orchid-log--mark-event-seen (session-id event-id)
  "Mark EVENT-ID as seen for SESSION-ID."
  (when event-id
    (when-let ((entry (orchid-log--get-entry session-id)))
      (puthash event-id t (plist-get entry :seen-events)))))



(provide 'log/orchid-log-registry)

;;; orchid-log-registry.el ends here
