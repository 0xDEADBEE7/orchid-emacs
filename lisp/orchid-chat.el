;;; orchid-chat.el --- IRC-style chat interface for Orchid -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; The primary user interface for Orchid.  An IRC-style chat buffer where
;; users type messages and see Claude's responses in real-time.
;; Uses two-cursor system for clean message flow.

;;; Code:

(require 'core/orchid-core)
(require 'session/orchid-session)
(require 'core/orchid-processing-indicator)
(require 'core/orchid-collapsible)
(require 'core/orchid-socket-view)
(require 'log/orchid-logging)
(require 'chat/orchid-chat-config)
(require 'chat/orchid-chat-session)
(require 'chat/orchid-chat-display)
(require 'chat/orchid-chat-history)
(require 'chat/orchid-chat-send)
(require 'chat/orchid-chat-slash)

;; Forward declarations for session browser
(declare-function orchid-session-browser-show "orchid-session-browser")
(declare-function orchid-chat-slash-maybe-open "chat/orchid-chat-slash")
(declare-function orchid-chat--clear-slash-input "chat/orchid-chat-slash")
(declare-function evil-define-key* "evil-core" (state keymap key def &rest bindings))
(defvar orchid-socket-view--region-start)

;;; Buffer-Local Variables
;; orchid-chat--session-id is declared in chat/orchid-chat-config

(defvar-local orchid-chat--input-marker nil
  "Marker for start of user input area.")

(defvar-local orchid-chat--assistant-cursor nil
  "Marker for assistant's streaming insertion point.")

(defvar-local orchid-chat--history-cursor nil
  "Marker for inserting older history at top of buffer.")

(defvar-local orchid-chat--loaded-event-ids nil
  "Hash table of event IDs already loaded in this buffer.
Used to prevent duplicates when loading more history.")


;;; Major Mode

(define-derived-mode orchid-chat-mode fundamental-mode "Orchid-Chat"
  "Major mode for Orchid chat buffers.
\\{orchid-chat-mode-map}"
  (add-hook 'post-self-insert-hook #'orchid-chat-slash-maybe-open nil t)
  (when (and (featurep 'evil) (fboundp 'evil-define-key*))
    (dolist (state '(normal motion))
      (evil-define-key* state orchid-chat-mode-map (kbd "TAB") #'orchid-chat-handle-tab))))

;;; Private Functions

(defun orchid-chat-handle-tab ()
  "Handle TAB key press.
If on a socket-view bar, toggle it.
If on a collapsible section, toggle it.
Otherwise, insert a tab character in the input area."
  (interactive)
  (cond
   ((orchid-socket-view-toggle-at-point) t)
   ((orchid-collapsible-toggle-at-point) t)
   ((>= (point) orchid-chat--input-marker) (insert "\t"))
   (t (message "Use TAB on collapsible sections to expand/collapse them"))))

(defun orchid-chat--setup-buffer (session-id _label)
  "Set up chat buffer for SESSION-ID with LABEL."
  (erase-buffer)

  ;; Enable invisibility for collapsible sections
  (setq buffer-invisibility-spec '())
  (add-to-invisibility-spec t)

  ;; Metadata section - only show for real sessions, not pending
  (unless (equal session-id "pending")
    (insert (orchid-chat--format-header-metadata session-id)))

  ;; Initial separator with workspace label
  (let* ((workspace-dir (when (not (equal session-id "pending"))
                          (when-let ((s (orchid-session-get session-id))
                                     (ws (or (plist-get s :working_dir)
                                             (plist-get s :workspace))))
                            (file-name-nondirectory (directory-file-name ws)))))
         (sep (orchid-chat--make-separator workspace-dir)))
    (insert (propertize (concat sep "\n\n") 'face 'orchid-chat-separator-face)))

  ;; Input area starts here
  (setq orchid-chat--input-marker (point-marker))
  (set-marker-insertion-type orchid-chat--input-marker nil)

  ;; Initialize assistant cursor at same position
  (orchid-chat--init-assistant-cursor (point)))

(defun orchid-chat--init-assistant-cursor (&optional position)
  "Initialize assistant cursor at POSITION or current point."
  (setq orchid-chat--assistant-cursor
        (copy-marker (or position (point)))))

(defun orchid-chat--ensure-assistant-cursor ()
  "Ensure assistant cursor exists and is valid."
  (unless (and (markerp orchid-chat--assistant-cursor)
               (marker-buffer orchid-chat--assistant-cursor))
    (orchid-chat--init-assistant-cursor
     (or orchid-chat--input-marker (point-max)))))

(defun orchid-chat--get-input ()
  "Get current input text."
  (when orchid-chat--input-marker
    (buffer-substring-no-properties
     orchid-chat--input-marker
     (point-max))))

(defun orchid-chat--clear-input ()
  "Clear input area."
  (when orchid-chat--input-marker
    (delete-region orchid-chat--input-marker (point-max))))

(defun orchid-chat--set-input (text)
  "Set input area to TEXT."
  (orchid-chat--clear-input)
  (goto-char (point-max))
  (insert text))

(defun orchid-chat-previous-input ()
  "No-op: persistent input history has been removed."
  (interactive)
  (message "Input history is not available."))

(defun orchid-chat-next-input ()
  "No-op: persistent input history has been removed."
  (interactive))

;;; Public API

(defun orchid-chat-close ()
  "Close current chat buffer and stop monitoring.
Cleanup is handled automatically by `kill-buffer-hook'."
  (interactive)
  (kill-buffer))

(defun orchid-chat-send-input ()
  "Send input from input area to Claude."
  (interactive)
  (orchid-log "[send-input] point=%d input-marker=%s evil-state=%s"
              (point)
              (and orchid-chat--input-marker (marker-position orchid-chat--input-marker))
              (and (boundp 'evil-state) evil-state))
  (if (and orchid-chat--input-marker (< (point) orchid-chat--input-marker))
      (insert "\n")
    (orchid-chat--send-message)))

(defun orchid-chat--send-message ()
  "Send message from input area."
  ;; Read input from after the bar, then tear down the sv region before
  ;; inserting the stub — so the stub never lands inside the sv region.
  (let ((message (orchid-chat--get-input-excluding-sv)))
    (orchid-log "[send-message] sv-region-end=%s input-marker=%s message=%S"
                (orchid-socket-view-region-end)
                (and orchid-chat--input-marker (marker-position orchid-chat--input-marker))
                message)
    (when message
      ;; Create a marker at region-end BEFORE stop so it tracks the position
      ;; through the deletion (integer snapshots shift when text is removed).
      (let ((insert-marker (copy-marker
                            (or (orchid-socket-view-region-end)
                                (marker-position orchid-chat--input-marker)))))
        (orchid-processing-stop)
        (orchid-socket-view-stop)
        ;; Re-anchor input-marker to the tracked position now that the
        ;; sv region (and the shared marker) have been torn down.
        (setq orchid-chat--input-marker insert-marker)
        (set-marker-insertion-type orchid-chat--input-marker nil))
      (orchid-chat--display-user-message message)
      (orchid-chat--prepare-for-response)
      (orchid-chat--send-to-existing-session message))))

(defun orchid-chat--get-input-excluding-sv ()
  "Get input text typed after the socket-view bar.
Reads from region-end (after the bar) to point-max when sv is active,
otherwise falls back to input-marker.  Returns nil if empty."
  (let* ((start (or (orchid-socket-view-region-end)
                    (and orchid-chat--input-marker
                         (marker-position orchid-chat--input-marker))))
         (text (when start
                 (string-trim
                  (buffer-substring-no-properties start (point-max))))))
    (orchid-log "[get-input] sv-active=%s start=%s point-max=%d text=%S"
                (and orchid-socket-view--region-start
                     (marker-buffer orchid-socket-view--region-start)
                     t)
                start (point-max) text)
    (when (and text (not (string-empty-p text)))
      text)))

(defun orchid-chat-newline ()
  "Insert a newline in input area."
  (interactive)
  (insert "\n"))

(defun orchid-chat-show-session-browser ()
  "Show session browser."
  (interactive)
  (require 'session/orchid-session-browser)
  (orchid-session-browser-show))

(provide 'orchid-chat)

;;; orchid-chat.el ends here
