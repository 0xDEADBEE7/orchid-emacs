;;; orchid-chat-config.el --- Faces, keymap, and separator for Orchid chat -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Faces, keymap definition, and separator utilities for orchid-chat.
;; Extracted from orchid-chat.el to keep individual files under 200 lines.

;;; Code:

(require 'core/orchid-faces)
(require 'session/orchid-session)

;;; Customization

(defgroup orchid-chat nil
  "Chat interface for Orchid."
  :group 'orchid
  :prefix "orchid-chat-")

(defcustom orchid-chat-input-history-size 100
  "Maximum number of input messages to remember."
  :type 'number
  :group 'orchid-chat)

;;; Faces

(defface orchid-chat-user-face
  '((t :inherit default :weight bold))
  "Face for user messages."
  :group 'orchid-chat)

;; orchid-chat-assistant-face and orchid-chat-separator-face are defined in
;; orchid-faces.el so that parser and log modules can use them without
;; creating an upward dependency on the chat layer.

;;; Separator Utilities

(defvar-local orchid-chat--session-id nil
  "Session ID for this chat buffer.")

(defun orchid-chat--make-separator (&optional label)
  "Return an 80-char separator line, optionally centered around LABEL.
Uses '─' characters with the label in the middle when LABEL is provided."
  (if (and label (not (string-empty-p label)))
      (let* ((total 80)
             (padded (format "  %s  " label))
             (pad-len (length padded))
             (side (max 0 (/ (- total pad-len) 2)))
             (left (make-string side ?─))
             (right (make-string (- total side pad-len) ?─)))
        (concat left padded right))
    (make-string 80 ?─)))

(defun orchid-chat--session-separator ()
  "Return separator string labeled with current session's workspace dirname."
  (let* ((s (when orchid-chat--session-id
               (orchid-session-get orchid-chat--session-id)))
         (ws (when s (or (plist-get s :working_dir) (plist-get s :workspace))))
         (label (when ws (file-name-nondirectory (directory-file-name ws)))))
    (orchid-chat--make-separator label)))

;;; Keymap

(declare-function orchid-chat-send-input "orchid-chat")
(declare-function orchid-chat-newline "orchid-chat")
(declare-function orchid-chat-close "orchid-chat")
(declare-function orchid-chat-show-session-browser "orchid-chat")
(declare-function orchid-chat-handle-tab "orchid-chat")
(declare-function orchid-chat-previous-input "orchid-chat")
(declare-function orchid-chat-next-input "orchid-chat")

(defvar orchid-chat-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") 'orchid-chat-send-input)
    (define-key map (kbd "S-<return>") 'orchid-chat-newline)
    (define-key map (kbd "C-c C-q") 'orchid-chat-close)
    (define-key map (kbd "C-c C-l") 'orchid-chat-show-session-browser)
    (define-key map (kbd "<backtab>") 'orchid-chat-show-session-browser)
    (define-key map (kbd "TAB") 'orchid-chat-handle-tab)
    (define-key map (kbd "M-p") 'orchid-chat-previous-input)
    (define-key map (kbd "M-n") 'orchid-chat-next-input)
    map)
  "Keymap for Orchid chat buffers.")

(provide 'chat/orchid-chat-config)

;;; orchid-chat-config.el ends here
