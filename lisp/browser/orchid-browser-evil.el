;;; orchid-browser-evil.el --- Evil mode support for session browser -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Optional Evil mode keybindings for `orchid-session-browser-mode'.
;; Loaded automatically when evil-mode is active.

;;; Code:

(declare-function orchid-session-browser-new "orchid-session-browser")
(declare-function orchid-session-browser-refresh "orchid-session-browser")
(declare-function orchid-session-browser-select "orchid-session-browser")
(declare-function orchid-session-browser-quit "orchid-session-browser")
(declare-function orchid-session-browser-move-down "orchid-session-browser")
(declare-function orchid-session-browser-move-up "orchid-session-browser")
(declare-function orchid-session-browser-page-down "orchid-session-browser")
(declare-function orchid-session-browser-page-up "orchid-session-browser")
(declare-function orchid-session-browser-mark-for-deletion "browser/orchid-browser-marks")
(declare-function orchid-session-browser-mark-for-kill "browser/orchid-browser-marks")
(declare-function orchid-session-browser-unmark "browser/orchid-browser-marks")
(declare-function orchid-session-browser-execute "browser/orchid-browser-marks")
(declare-function orchid-session-browser-search "browser/orchid-browser-search")
(declare-function orchid-session-browser-search-clear "browser/orchid-browser-search")
(declare-function evil-define-key* "evil-core" (state keymap key def &rest bindings))

(defvar orchid-session-browser-mode-map)

(defun orchid-browser-setup-evil-keybindings ()
  "Setup Evil mode keybindings for session browser."
  (when (and (featurep 'evil) (fboundp 'evil-define-key*) (bound-and-true-p evil-mode))
    (ignore-errors
      (dolist (state '(normal motion))
        (evil-define-key* state orchid-session-browser-mode-map
          (kbd "RET") #'orchid-session-browser-select
          (kbd "n")   #'orchid-session-browser-new
          (kbd "q")   #'orchid-session-browser-quit
          (kbd "r")   #'orchid-session-browser-refresh
          (kbd "g")   #'orchid-session-browser-refresh
          (kbd "D")   #'orchid-session-browser-mark-for-deletion
          (kbd "S")   #'orchid-session-browser-mark-for-kill
          (kbd "u")   #'orchid-session-browser-unmark
          (kbd "x")   #'orchid-session-browser-execute
          (kbd "/")   #'orchid-session-browser-search
          (kbd "a")   #'orchid-session-browser-search
          (kbd "d")   #'orchid-session-browser-search-clear
          (kbd "j")   #'orchid-session-browser-move-down
          (kbd "k")   #'orchid-session-browser-move-up
          (kbd "J")   #'orchid-session-browser-page-down
          (kbd "K")   #'orchid-session-browser-page-up)))))

(provide 'browser/orchid-browser-evil)

;;; orchid-browser-evil.el ends here
