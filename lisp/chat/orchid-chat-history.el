;;; orchid-chat-history.el --- Load-more history for Orchid chat -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Load-more history functionality for the Orchid chat buffer.
;; Extracted from orchid-chat.el to keep individual files under 200 lines.

;;; Code:

(require 'orchid-log)
(require 'chat/orchid-chat-config)

;; Forward declarations for chat vars and functions
(declare-function orchid-chat-insert-log-line "orchid-chat")
(defvar orchid-chat--loaded-event-ids)
(defvar orchid-chat--history-cursor)
(defvar orchid-chat--assistant-cursor)

(defun orchid-chat-load-more-history ()
  "Load more history at the top of the buffer."
  (interactive)
  (unless orchid-chat--session-id
    (error "No active session"))
  (unless orchid-chat--loaded-event-ids
    (error "No history tracking initialized"))
  (unless orchid-chat--history-cursor
    (error "History cursor not initialized"))

  (let ((buffer (current-buffer))
        (batch-size (or orchid-log-restore-max-events 100)))
    (message "Loading %d more events..." batch-size)

    (let ((saved-assistant-cursor (marker-position orchid-chat--assistant-cursor)))
      (set-marker orchid-chat--assistant-cursor orchid-chat--history-cursor)

      (let* ((result (orchid-log-restore-session
                      orchid-chat--session-id
                      (lambda (parsed-event)
                        (orchid-chat-insert-log-line buffer parsed-event))
                      orchid-chat--loaded-event-ids
                      batch-size))
             (count (plist-get result :count))
             (seen-events (plist-get result :seen-events)))

        (set-marker orchid-chat--assistant-cursor saved-assistant-cursor)
        (setq orchid-chat--loaded-event-ids seen-events)

        (if (> count 0)
            (progn
              (message "Loaded %d more events" count))
          (message "No more history to load"))))))

(provide 'chat/orchid-chat-history)

;;; orchid-chat-history.el ends here
