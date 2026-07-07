;;; orchid-faces.el --- Shared faces for Orchid -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Shared face definitions used across multiple layers (log, parsers, chat).
;; Keeping these here prevents upward layer dependencies: parsers and log
;; modules can require this file without depending on the chat layer.

;;; Code:

(defgroup orchid-faces nil
  "Faces for Orchid chat and log display."
  :group 'orchid
  :prefix "orchid-")

(defface orchid-chat-assistant-face
  '((t :inherit shadow :weight bold))
  "Face for assistant messages."
  :group 'orchid-faces)

(defface orchid-chat-separator-face
  '((t :inherit shadow))
  "Face for message separators."
  :group 'orchid-faces)

(defface orchid-button
  '((t :foreground "#cc4444" :weight bold))
  "Face for Orchid action buttons."
  :group 'orchid-faces)

(defface orchid-socket-view-header-face
  '((t :inherit orchid-chat-separator-face))
  "Face for the socket view collapsible header bar."
  :group 'orchid-faces)

(defface orchid-socket-view-border-face
  '((t :inherit default))
  "Face for the shell box borders and command line — matches user message stubs."
  :group 'orchid-faces)

(provide 'core/orchid-faces)

;;; orchid-faces.el ends here
