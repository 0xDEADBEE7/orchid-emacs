;;; orchid.el --- Emacs interface for Claude Code CLI -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Version: 1.0.0
;; Package-Requires: ((emacs "27.1") (seek "0.1"))
;; Keywords: tools, ai, claude
;; URL: https://github.com/yourusername/orchid

;;; Commentary:

;; Orchid provides an IRC-style chat interface for Claude Code within Emacs.
;; It wraps the `orchid` CLI tool and displays conversations in real-time.
;;
;; Features:
;; - IRC-style chat buffer with multi-line input (Shift-RET)
;; - Real-time log monitoring with enhanced parsing
;; - Simple session browser with status indicators
;; - Message timestamps
;; - Comprehensive error handling
;; - Centralized configuration
;;
;; Quick Start:
;;   1. Ensure `orchid` CLI is installed and in PATH
;;   2. Load this package: (require 'orchid)
;;   3. Run M-x orchid to open the session browser
;;   4. Use j/k to navigate, RET to open a session
;;   5. Type messages and press RET to send
;;   6. Use Shift-RET for multi-line input
;;
;; Alternative entry points:
;;   M-x orchid-open-session - Directly open a session by ID/label
;;   M-x orchid-new-session - Create a new session with persona selection
;;   M-x orchid-session-browser-show - Show session browser
;;   M-x orchid-check-cli - Verify CLI installation

;;; Code:

(add-to-list 'load-path (file-name-as-directory
                         (concat (file-name-directory
                                 (or load-file-name buffer-file-name))
                                "lisp")))

(require 'core/orchid-core)
(require 'session/orchid-session)
(require 'session/orchid-session-browser)

(declare-function orchid-chat-open-new "orchid-chat" (&optional policy prompt))
(declare-function orchid-session-browser--fetch-policies "browser/orchid-browser-populate")

;;; Customization

(defgroup orchid nil
  "Emacs interface for Claude Code CLI."
  :group 'tools
  :prefix "orchid-")

;;; Public Commands

;;;###autoload
(defun orchid ()
  "Open Orchid session browser.
This is the main entry point for Orchid operations."
  (interactive)
  (orchid-session-browser-show))

;;;###autoload
(defun orchid-open-session (session-id-or-label)
  "Open chat buffer for SESSION-ID-OR-LABEL.
First refreshes the session list from the CLI, then opens the chat buffer."
  (interactive "sSession ID or label: ")
  (message "Refreshing sessions...")
  (orchid-session-refresh
   (lambda (_sessions)
     (condition-case err
         (progn
           (orchid-session-open session-id-or-label)
           (message "Opened session: %s" session-id-or-label))
       (error
        (message "Failed to open session: %s" (error-message-string err)))))))

;;;###autoload
(defun orchid-list-sessions ()
  "List all available sessions.
Refreshes from CLI and displays in messages buffer."
  (interactive)
  (message "Refreshing sessions...")
  (orchid-session-refresh
   (lambda (sessions)
     (if sessions
         (let ((session-info
                (mapconcat
                 (lambda (s)
                   (format "  %s (%s)"
                           (plist-get s :label)
                           (plist-get s :id)))
                 sessions
                 "\n")))
           (message "Available sessions:\n%s" session-info))
       (message "No sessions found")))))

;;;###autoload
(defun orchid-check-cli ()
  "Check if orchid CLI is available."
  (interactive)
  (if (orchid-core-cli-available-p)
      (orchid-core-get-version
       (lambda (result)
         (if (plist-get result :success)
             (message "orchid CLI found: %s" (plist-get result :raw))
           (message "orchid CLI found but version check failed"))))
    (message "orchid CLI not found in PATH. Please install it.")))

;;;###autoload
(defun orchid-new-session (&optional policy prompt)
  "Create a new session with optional POLICY and PROMPT."
  (interactive
   (let ((policies (orchid-session-browser--fetch-policies)))
     (list (when policies (completing-read "Policy: " policies nil t)) nil)))
  (require 'orchid-chat)
  (orchid-chat-open-new policy prompt))

;;; Package Footer

(provide 'orchid)

;;; orchid.el ends here
