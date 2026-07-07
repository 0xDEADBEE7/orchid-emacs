;;; orchid-chat-send.el --- Send message logic for Orchid chat -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Message sending and response handling for the Orchid chat interface.
;; Extracted from orchid-chat.el to keep files under 200 lines.

;;; Code:

(require 'core/orchid-core)
(require 'orchid-log)
(require 'core/orchid-collapsible)
(require 'core/orchid-processing-indicator)
(require 'core/orchid-socket-view)
(require 'parsers/orchid-parser-utils)
(require 'chat/orchid-chat-config)
(require 'log/orchid-log-monitor)

;; Forward declarations
(declare-function orchid-chat--make-separator "chat/orchid-chat-config")
(declare-function orchid-chat--session-separator "chat/orchid-chat-config")
(declare-function orchid-chat-insert-system-message "orchid-chat")
(declare-function orchid-chat--init-assistant-cursor "orchid-chat")
(declare-function orchid-parser--format-stub-with-timestamp "orchid-parser-utils")
(declare-function orchid-chat-insert-log-line "orchid-chat" (buffer parsed-event))
(declare-function orchid-log-monitoring-p "orchid-log" (session-id))
(declare-function orchid-log-start-monitoring-with-retry "log/orchid-log-monitor"
                  (session-id callback max-retries retry-interval))
(defvar orchid-chat--input-marker)
(defvar orchid-chat--assistant-cursor)
(defvar orchid-socket-view--region-end)

(defun orchid-chat--display-user-message (message)
  "Display user MESSAGE in buffer as a collapsed stub."
  (let ((inhibit-read-only t))
    (goto-char orchid-chat--input-marker)
    (delete-region orchid-chat--input-marker (point-max))
    (let* ((clean-text (replace-regexp-in-string "\n" " " message))
           (preview (if (> (length clean-text) 50)
                       (concat (substring clean-text 0 47) "...")
                     clean-text))
           (timestamp (format-time-string "%Y-%m-%dT%H:%M:%S%z"))
           (base-stub (format "[User: %s]" preview))
           (stub (orchid-parser--format-stub-with-timestamp base-stub timestamp))
           (user-stub (orchid-collapsible-create stub message t 'orchid-collapsible-user-stub-face))
           (start-pos (point)))
      (insert user-stub)
      (save-excursion
        (goto-char start-pos)
        (when-let ((section-id (get-text-property (point) 'orchid-collapsible-id)))
          (add-to-invisibility-spec section-id)))
      (insert "\n"))))

(defun orchid-chat--prepare-for-response ()
  "Prepare buffer for assistant response.
Called after sv and processing have already been stopped by send-message."
  (orchid-chat--init-assistant-cursor (point))
  (let* ((sep (orchid-chat--session-separator)))
    (insert (propertize sep 'face 'orchid-chat-separator-face)))
  (insert "\n")
  (orchid-socket-view-start orchid-chat--session-id (point))
  ;; Insert a plain sentinel newline AFTER region-end without letting region-end
  ;; advance over it.  region-end has insertion-type t, so we must temporarily
  ;; set it to nil, insert, then restore.  This guarantees point-max > region-end
  ;; so get-input-excluding-sv can read text typed after the bar.
  (set-marker-insertion-type orchid-socket-view--region-end nil)
  (save-excursion
    (goto-char (marker-position orchid-socket-view--region-end))
    (insert "\n"))
  (set-marker-insertion-type orchid-socket-view--region-end t)
  ;; Use the sv module's own region-end marker as input-marker so that it
  ;; tracks forward automatically as tool-output body is inserted into the
  ;; region (region-end has insertion-type t).  A copy would drift.
  (setq orchid-chat--input-marker orchid-socket-view--region-end)
  ;; sv--insert uses save-excursion so point is still at the bar's start
  ;; (inside the read-only region).  Move to the editable area after the bar.
  (goto-char (point-max)))

(defun orchid-chat--send-to-existing-session (message)
  "Send MESSAGE to existing session."
  (let ((buffer (current-buffer)))
    (orchid-log "Sending to existing session: %s" orchid-chat--session-id)
    (orchid-core-send
     message
     orchid-chat--session-id
     :callback (lambda (result)
                (orchid-chat--handle-send-result result buffer)))))

(defun orchid-chat--handle-send-result (result buffer)
  "Handle RESULT from session send for BUFFER."
  (orchid-log "Send callback: success=%s data=%S raw=%s"
              (plist-get result :success)
              (plist-get result :data)
              (plist-get result :raw))
  (if (plist-get result :success)
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          ;; Start monitoring on first send if not already started (new session)
          (unless (orchid-log-monitoring-p orchid-chat--session-id)
            (orchid-log "[send] starting log monitoring for new session %s" orchid-chat--session-id)
            (orchid-log-start-monitoring-with-retry
             orchid-chat--session-id
             (lambda (parsed-event)
               (orchid-chat-insert-log-line buffer parsed-event))
             20 1))
          (save-excursion
            (goto-char orchid-chat--assistant-cursor)
            (orchid-processing-capture-chunk-baseline orchid-chat--session-id)
            (orchid-processing-show orchid-chat--session-id))))
    (let ((error-msg (or (plist-get result :error)
                        (plist-get result :raw)
                        (format "Exit code: %s" (plist-get result :exit-code)))))
      (orchid-log "Send failed: %s" error-msg)
      (orchid-chat-insert-system-message
       (format "Send failed:\n%s" error-msg)))))

(provide 'chat/orchid-chat-send)

;;; orchid-chat-send.el ends here
