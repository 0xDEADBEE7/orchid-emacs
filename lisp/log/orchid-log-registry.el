;;; orchid-log-registry.el --- Session registry for log monitoring -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Manages the registry of active log monitoring sessions.
;; Tracks position and event deduplication for each session.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'log/orchid-logging)

(defvar orchid-log--registry nil
  "List of monitoring entries.
Each entry is a plist with :session-id, :log-file, :buffer,
:callback, :last-position, and :seen-events.")

(defun orchid-log--register (session-id log-file buffer callback &optional seen-events file-position)
  "Register monitoring entry for SESSION-ID.
SEEN-EVENTS contains IDs already displayed during history restoration.
FILE-POSITION is the byte offset through LOG-FILE already loaded."
  (push (list :session-id session-id
              :log-file log-file
              :buffer buffer
              :callback callback
              :last-position
              (with-current-buffer buffer
                (goto-char (point-max))
                (if (bolp) (point) (line-beginning-position)))
              :file-position file-position
              :seen-events (or seen-events (make-hash-table :test 'equal)))
        orchid-log--registry))

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
  "Update the character position processed for SESSION-ID."
  (when-let ((entry (orchid-log--get-entry session-id)))
    (plist-put entry :last-position pos)))

(defun orchid-log--set-file-position (session-id position)
  "Update the byte position read for SESSION-ID."
  (when-let ((entry (orchid-log--get-entry session-id)))
    (plist-put entry :file-position position)))
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
