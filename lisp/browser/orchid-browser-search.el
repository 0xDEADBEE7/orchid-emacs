;;; orchid-browser-search.el --- Search functionality for session browser -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Search mode for Orchid session browser using keymap-swap pattern.

;;; Code:

(declare-function orchid-session-browser--populate "browser/orchid-browser-populate")
(declare-function evil-emacs-state "evil-states" (&optional arg))
(declare-function evil-normal-state "evil-states" (&optional arg))

(defvar orchid-session-browser-mode-map)
(defvar-local orchid-session-browser--mode 'normal)
(defvar-local orchid-session-browser--search-query "")
(defvar-local orchid-session-browser--selected 0)
(defvar-local orchid-session-browser--scroll-offset 0)

;;; Fuzzy match

(defun orchid-browser--fuzzy-match (query text)
  "Return non-nil if all chars of QUERY appear in order in TEXT (case-insensitive)."
  (when (and query text)
    (let ((q (downcase query))
          (s (downcase text))
          (pos 0))
      (catch 'done
        (dolist (char (string-to-list q))
          (setq pos (string-match (regexp-quote (char-to-string char)) s pos))
          (if pos (setq pos (1+ pos)) (throw 'done nil)))
        t))))

;;; Search keymap
;;
;; Installed via `minor-mode-overriding-map-alist' so it takes precedence over
;; evil keymaps without needing to switch evil state.

(defvar orchid-session-browser-search-map
  (let ((map (make-sparse-keymap)))
    (let ((i 32))
      (while (<= i 126)
        (define-key map (vector i) #'orchid-session-browser-search-self-insert)
        (setq i (1+ i))))
    (define-key map (kbd "DEL")         #'orchid-session-browser-search-backspace)
    (define-key map (kbd "<backspace>") #'orchid-session-browser-search-backspace)
    (define-key map (kbd "RET")         #'orchid-session-browser-search-exit)
    (define-key map [escape]            #'orchid-session-browser-search-exit)
    (define-key map (kbd "C-g")         #'orchid-session-browser-search-clear)
    map)
  "Keymap active while search mode is engaged in the session browser.")

;;; Search commands

(defun orchid-session-browser-search ()
  "Enter search mode."
  (interactive)
  (setq orchid-session-browser--mode 'search)
  (when (fboundp 'evil-emacs-state) (evil-emacs-state))
  (use-local-map orchid-session-browser-search-map)
  (orchid-session-browser--populate))

(defun orchid-session-browser-search-exit ()
  "Exit search mode."
  (interactive)
  (setq orchid-session-browser--mode 'normal)
  (use-local-map orchid-session-browser-mode-map)
  (when (fboundp 'evil-normal-state) (evil-normal-state))
  (orchid-session-browser--populate))

(defun orchid-session-browser-search-clear ()
  "Clear search query and exit search mode."
  (interactive)
  (setq orchid-session-browser--search-query ""
        orchid-session-browser--selected 0
        orchid-session-browser--scroll-offset 0)
  (orchid-session-browser-search-exit))

(defun orchid-session-browser-search-self-insert ()
  "Append the last typed character to the search query."
  (interactive)
  (setq orchid-session-browser--search-query
        (concat orchid-session-browser--search-query
                (char-to-string last-command-event)))
  (orchid-session-browser--populate))

(defun orchid-session-browser-search-backspace ()
  "Remove last character from the search query."
  (interactive)
  (when (> (length orchid-session-browser--search-query) 0)
    (setq orchid-session-browser--search-query
          (substring orchid-session-browser--search-query 0 -1))
    (orchid-session-browser--populate)))

(provide 'browser/orchid-browser-search)

;;; orchid-browser-search.el ends here
