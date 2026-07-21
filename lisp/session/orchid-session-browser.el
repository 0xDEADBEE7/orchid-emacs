;;; orchid-session-browser.el --- Session browser for Orchid -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Tabular browser for listing, opening, and managing Orchid sessions.
;; Supports keyboard navigation, fuzzy search, and batch mark/execute operations.

;;; Code:

(require 'cl-lib)
(require 'core/orchid-core)
(require 'session/orchid-session)
(require 'browser/orchid-browser-search)
(require 'browser/orchid-browser-evil)
(require 'browser/orchid-browser-format)
(require 'browser/orchid-browser-marks)
(require 'browser/orchid-browser-populate)

(declare-function orchid-chat-open-new "orchid-chat" (&optional policy prompt))
(declare-function orchid-session-notify-status-change "orchid-session" (session-id running))

;;; Configuration

(defgroup orchid-session-browser nil
  "Session browser for Orchid."
  :group 'orchid
  :prefix "orchid-session-browser-")

(defcustom orchid-session-browser-buffer-name "*orchid-sessions*"
  "Buffer name for the session browser."
  :type 'string
  :group 'orchid-session-browser)

(defface orchid-session-browser-header
  '((t :inherit header-line))
  "Face for browser header."
  :group 'orchid-session-browser)

(defface orchid-session-browser-help
  '((t :inherit font-lock-comment-face))
  "Face for help text."
  :group 'orchid-session-browser)

(defface orchid-session-browser-active
  '((t :inherit success :weight bold))
  "Face for active sessions."
  :group 'orchid-session-browser)

(defface orchid-session-browser-idle
  '((t :inherit shadow))
  "Face for idle sessions."
  :group 'orchid-session-browser)

(defface orchid-session-browser-separator-face
  '((t :inherit shadow))
  "Face for table separators."
  :group 'orchid-session-browser)

;;; Private Functions

(defun orchid-session-browser--on-status-change (session-id _running)
  "Redraw browser if SESSION-ID is currently visible in the scroll window."
  (when (buffer-live-p (get-buffer orchid-session-browser-buffer-name))
    (with-current-buffer orchid-session-browser-buffer-name
      (when (eq major-mode 'orchid-session-browser-mode)
        (let* ((b (orchid-session-browser--make-browser))
               (rows (seek-filtered-rows b))
               (off orchid-session-browser--scroll-offset)
               (end (min (+ off (seek-visible-rows b)) (length rows)))
               (visible (seq-subseq rows (min off (length rows)) end)))
          (when (cl-find session-id visible
                         :key (lambda (s) (plist-get s :id))
                         :test #'equal)
            (orchid-session-browser--invalidate-row session-id)
            (orchid-session-browser--populate)))))))

(defun orchid-session-browser-move-down ()
  "Move selection down one row."
  (interactive)
  (cl-incf orchid-session-browser--selected)
  (orchid-session-browser--populate))

(defun orchid-session-browser-move-up ()
  "Move selection up one row."
  (interactive)
  (cl-decf orchid-session-browser--selected)
  (orchid-session-browser--populate))

(defun orchid-session-browser-page-down ()
  "Move selection down one page."
  (interactive)
  (cl-incf orchid-session-browser--selected
           (seek-visible-rows (orchid-session-browser--make-browser)))
  (orchid-session-browser--populate))

(defun orchid-session-browser-page-up ()
  "Move selection up one page."
  (interactive)
  (cl-decf orchid-session-browser--selected
           (seek-visible-rows (orchid-session-browser--make-browser)))
  (orchid-session-browser--populate))

;;; Interactive Commands

(defun orchid-session-browser-select ()
  "Open the currently selected session and close the browser."
  (interactive)
  (when-let ((session (orchid-session-browser--selected-session)))
    (let* ((session-id (plist-get session :id))
           (existing-buffer (plist-get session :chat-buffer))
           (buf (when (and existing-buffer (buffer-live-p existing-buffer))
                  existing-buffer))
           (browser-buf (get-buffer orchid-session-browser-buffer-name)))
      (if buf
          (switch-to-buffer buf)
        (when-let ((opened (orchid-session-open session-id)))
          (switch-to-buffer opened)))
      (when (buffer-live-p browser-buf)
        (kill-buffer browser-buf)))))

(defun orchid-session-browser-new ()
  "Start a new chat session, prompting for policy and prompt selection."
  (interactive)
  (let* ((policies (orchid-session-browser--fetch-policies))
         (prompts (orchid-session-browser--fetch-prompts))
         (policy (when policies (completing-read "Policy: " policies nil t)))
         (prompt (when prompts (completing-read "Prompt (optional): " (cons "" prompts) nil t))))
    (require 'orchid-chat)
    (orchid-chat-open-new policy (unless (string-empty-p (or prompt "")) prompt))))

(defun orchid-session-browser-refresh ()
  "Refresh session list from CLI and update browser."
  (interactive)
  (when (eq orchid-session-browser--mode 'search)
    (orchid-session-browser-search-exit))
  (orchid-session-refresh)
  (orchid-session-browser--populate))

(defun orchid-session-browser-quit ()
  "Quit session browser."
  (interactive)
  (when (eq orchid-session-browser--mode 'search)
    (orchid-session-browser-search-exit))
  (quit-window t))

;;; Major Mode

(defvar orchid-session-browser-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'orchid-session-browser-select)
    (define-key map (kbd "n")   #'orchid-session-browser-new)
    (define-key map (kbd "q")   #'orchid-session-browser-quit)
    (define-key map (kbd "r")   #'orchid-session-browser-refresh)
    (define-key map (kbd "g")   #'orchid-session-browser-refresh)
    (define-key map (kbd "D")   #'orchid-session-browser-mark-for-deletion)
    (define-key map (kbd "S")   #'orchid-session-browser-mark-for-kill)
    (define-key map (kbd "u")   #'orchid-session-browser-unmark)
    (define-key map (kbd "x")   #'orchid-session-browser-execute)
    (define-key map (kbd "/")   #'orchid-session-browser-search)
    (define-key map (kbd "a")   #'orchid-session-browser-search)
    (define-key map (kbd "d")   #'orchid-session-browser-search-clear)
    (define-key map (kbd "j")   #'orchid-session-browser-move-down)
    (define-key map (kbd "k")   #'orchid-session-browser-move-up)
    (define-key map (kbd "J")   #'orchid-session-browser-page-down)
    (define-key map (kbd "K")   #'orchid-session-browser-page-up)
    (define-key map (kbd "p")   #'orchid-session-browser-move-up)
    map)
  "Keymap for `orchid-session-browser-mode'.")

(define-derived-mode orchid-session-browser-mode special-mode "Orchid-Sessions"
  "Major mode for browsing Orchid sessions."
  (setq truncate-lines t)
  (setq buffer-read-only t)
  (setq-local orchid-session-browser--search-query "")
  (setq-local orchid-session-browser--selected 0)
  (setq-local orchid-session-browser--scroll-offset 0)
  (setq-local orchid-session-browser--mode 'normal)
  (orchid-browser-setup-evil-keybindings)
  (add-hook 'orchid-session-status-change-functions
            #'orchid-session-browser--on-status-change)
  (add-hook 'kill-buffer-hook
            (lambda ()
              (remove-hook 'orchid-session-status-change-functions
                           #'orchid-session-browser--on-status-change))
            nil t))

;;; Public API

;;;###autoload
(defun orchid-session-browser-show ()
  "Show session browser buffer."
  (interactive)
  (let ((buffer (get-buffer-create orchid-session-browser-buffer-name)))
    (switch-to-buffer buffer)
    (unless (eq major-mode 'orchid-session-browser-mode)
      (orchid-session-browser-mode))
    (orchid-session-refresh)
    (orchid-session-browser--populate)))

(provide 'session/orchid-session-browser)

;;; orchid-session-browser.el ends here
