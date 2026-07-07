;;; orchid-chat-display.el --- Message display and formatting for Orchid chat -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Handles message insertion, collapsible section registration,
;; and display formatting for the Orchid chat interface.

;;; Code:

(require 'core/orchid-processing-indicator)

;; Forward declarations for chat functions
(declare-function orchid-chat--ensure-assistant-cursor "orchid-chat")

;; Buffer-local variables declared in orchid-chat.el
(defvar orchid-chat--assistant-cursor)
(defvar orchid-chat--input-marker)

;;; Public API

(defun orchid-chat--insert-at-assistant-cursor (text)
  "Insert TEXT at assistant cursor position.
Registers any collapsible sections in the buffer's invisibility spec."
  (orchid-chat--ensure-assistant-cursor)
  (save-excursion
    (goto-char orchid-chat--assistant-cursor)
    (let ((start (point)))
      (insert text)
      (set-marker orchid-chat--assistant-cursor (point))
      ;; Register any collapsible section IDs in invisibility spec
      (orchid-chat--register-collapsible-sections start (point)))))

(defun orchid-chat--register-collapsible-sections (start end)
  "Register collapsible section IDs in buffer's invisibility spec.
Scans region from START to END for collapsible sections."
  (save-excursion
    (goto-char start)
    (let ((pos start)
          (seen-ids nil))
      (while (< pos end)
        (let ((section-id (get-text-property pos 'orchid-collapsible-id)))
          (when (and section-id (not (member section-id seen-ids)))
            ;; Found a new section ID, add to invisibility spec
            (unless (member section-id buffer-invisibility-spec)
              (add-to-invisibility-spec section-id))
            (push section-id seen-ids)))
        (setq pos (or (next-single-property-change pos 'orchid-collapsible-id nil end) end))))))

(defun orchid-chat-insert-system-message (message)
  "Insert system MESSAGE into conversation area."
  (save-excursion
    (goto-char (point-max))
    (insert "\n")
    (insert (propertize (concat (make-string 80 ?─) "\n") 'face 'orchid-chat-separator-face))
    (insert (propertize (concat "[SYSTEM] " message "\n") 'face 'warning))
    (insert (propertize (concat (make-string 80 ?─) "\n\n") 'face 'orchid-chat-separator-face))
    (setq orchid-chat--input-marker (point-marker))))

(defun orchid-chat-insert-log-line (buffer parsed-event)
  "Insert PARSED-EVENT into BUFFER's conversation area.
PARSED-EVENT is a plist with :display and :event-type keys.
Content is inserted at assistant cursor, before the processing indicator.
Processing indicator is automatically stopped when the Claude process exits."
  (when (and parsed-event (buffer-live-p buffer))
    (with-current-buffer buffer
      (let* ((at-end (>= (point) (point-max)))
             (display-text (plist-get parsed-event :display))
             (event-type (plist-get parsed-event :event-type)))

        ;; Update processing indicator status based on event type
        (cond
         ((equal event-type "assistant")
          (orchid-processing-update-status "Thinking"))
         ((equal event-type "tool_call")
          (orchid-processing-update-status "Running tool"))
         ((equal event-type "tool_result")
          (orchid-processing-update-status "Processing result")))

        ;; Insert display text if non-empty
        (when (and display-text (not (string-empty-p display-text)))
          (orchid-chat--insert-at-assistant-cursor display-text)
          (orchid-chat--insert-at-assistant-cursor "\n"))

        ;; Auto-scroll if at end
        (when at-end
          (goto-char (point-max)))))))

(provide 'chat/orchid-chat-display)

;;; orchid-chat-display.el ends here
