;;; orchid-session.el --- Session management for Orchid -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Track orchid conversations within Emacs.  Maintains mappings between
;; conversation IDs, chat buffers, and log monitors.  The `orchid` CLI is the
;; source of truth; this component caches and tracks sessions for UI purposes.

;;; Code:

(require 'core/orchid-core)
(require 'json)
(require 'cl-lib)

;; Forward declarations to avoid circular dependencies
(declare-function orchid-chat-open "orchid-chat" (session-id))
(declare-function orchid-log-get-buffer "orchid-log" (session-id))
(declare-function orchid-log-monitoring-p "orchid-log" (session-id))
(declare-function orchid-log-stop-monitoring "orchid-log" (session-id))

;;; Customization

(defgroup orchid-session nil
  "Session management for Orchid."
  :group 'orchid
  :prefix "orchid-session-")

;;; Private Variables

(defvar orchid-session--registry nil
  "Alist mapping session-id to session plist.")

(defvar-local orchid-session--current nil
  "Current session ID for this buffer.")

;;; Status change hook

(defvar orchid-session-status-change-functions nil
  "Abnormal hook called when a session's running status changes.
Each function receives (SESSION-ID RUNNING) where RUNNING is t or nil.")

(defun orchid-session-notify-status-change (session-id running)
  "Update :running for SESSION-ID in registry and run status-change hook.
RUNNING is t when the session is active, nil when idle."
  (when-let ((session (orchid-session-get session-id)))
    (plist-put session :running running))
  (run-hook-with-args 'orchid-session-status-change-functions session-id running))

;;; Private Functions

(defun orchid-session--read-metadata (session-id)
  "Read metadata and runtime state for SESSION-ID and merge them.
Metadata is identity/configuration; state supplies runtime fields."
  (let ((path (orchid-core-session-metadata-path session-id))
        (state-path (orchid-core-session-state-path session-id)))
    (when (file-exists-p path)
      (condition-case nil
          (let ((metadata (with-temp-buffer
                            (insert-file-contents path)
                            (json-parse-buffer :object-type 'plist :array-type 'list)))
                (state (when (file-exists-p state-path)
                         (with-temp-buffer
                           (insert-file-contents state-path)
                           (json-parse-buffer :object-type 'plist :array-type 'list)))))
            (if state (append state metadata) metadata))
        (error nil)))))

(defun orchid-session--preserve-state (session)
  "Preserve Emacs-local state in SESSION from existing registry."
  (when-let* ((session-id (plist-get session :id))
              (existing (alist-get session-id orchid-session--registry
                                   nil nil #'equal)))
    (dolist (prop '(:chat-buffer :log-buffer :monitoring-p))
      (when-let ((value (plist-get existing prop)))
        (plist-put session prop value)))))

(defun orchid-session--update-registry (sessions)
  "Update registry with SESSIONS list from CLI.
Preserves Emacs-local state like chat and log buffers."
  (let ((new-registry nil))
    (dolist (session sessions)
      (let ((session-id (plist-get session :id)))
        (when session-id
          (orchid-session--preserve-state session)
          (push (cons session-id session) new-registry))))
    (setq orchid-session--registry new-registry)))

(defun orchid-session-register (session)
  "Add or replace SESSION in the registry.
Use when a session is created locally without a full list refresh."
  (when-let ((session-id (plist-get session :id)))
    (orchid-session--preserve-state session)
    (setq orchid-session--registry
          (cons (cons session-id session)
                (assoc-delete-all session-id orchid-session--registry)))))

;;; Public API

(defun orchid-session-refresh (&optional callback)
  "Refresh session list from CLI.  Async if CALLBACK provided."
  (if callback
      (orchid-core-list
       (lambda (result)
         (if (plist-get result :success)
             (let ((sessions (plist-get result :data)))
               (orchid-session--update-registry sessions)
               (funcall callback sessions))
           (message "Orchid: Failed to refresh sessions: %s"
                    (plist-get result :error)))))
    (let ((result (orchid-core-list)))
      (if (plist-get result :success)
          (let ((sessions (plist-get result :data)))
            (orchid-session--update-registry sessions)
            sessions)
        (error "Failed to refresh: %s" (plist-get result :error))))))

(defun orchid-session-list ()
  "Get all cached sessions."
  (mapcar #'cdr orchid-session--registry))

(defun orchid-session-get (session-id-or-label)
  "Get session by SESSION-ID-OR-LABEL (try ID first, then label)."
  (or (alist-get session-id-or-label orchid-session--registry nil nil #'equal)
      (when-let ((entry (cl-find-if
                         (lambda (e)
                           (equal session-id-or-label
                                  (plist-get (cdr e) :label)))
                         orchid-session--registry)))
        (cdr entry))))

(defun orchid-session-get-chat-buffer (session-id)
  "Get chat buffer for SESSION-ID."
  (when-let ((session (orchid-session-get session-id)))
    (plist-get session :chat-buffer)))

(defun orchid-session-get-log-buffer (session-id)
  "Get log buffer for SESSION-ID."
  (when-let ((session (orchid-session-get session-id)))
    (plist-get session :log-buffer)))

(defun orchid-session-monitoring-p (session-id)
  "Check if SESSION-ID is being monitored."
  (when-let ((session (orchid-session-get session-id)))
    (plist-get session :monitoring-p)))

(defun orchid-session-running-p (session-id)
  "Return the cached :running value for SESSION-ID."
  (when-let ((session (orchid-session-get session-id)))
    (plist-get session :running)))

(defun orchid-session-current ()
  "Get current session ID."
  orchid-session--current)

(defun orchid-session-set-current (session-id)
  "Set current session ID to SESSION-ID."
  (setq orchid-session--current session-id))

(defun orchid-session-open (session-id)
  "Open chat buffer and start monitoring for SESSION-ID."
  (let ((session (or (orchid-session-get session-id)
                     (progn (orchid-session-refresh)
                            (orchid-session-get session-id)))))
    (unless session
      (error "Session '%s' not found" session-id))

    ;; Clean up dead buffers
    (when-let ((chat-buffer (plist-get session :chat-buffer)))
      (unless (buffer-live-p chat-buffer)
        (plist-put session :chat-buffer nil)))
    (when-let ((log-buffer (plist-get session :log-buffer)))
      (unless (buffer-live-p log-buffer)
        (plist-put session :log-buffer nil)
        (plist-put session :monitoring-p nil)))

    ;; Stop leftover monitoring
    (when (plist-get session :monitoring-p)
      (require 'orchid-log)
      (when (orchid-log-monitoring-p session-id)
        (orchid-log-stop-monitoring session-id))
      (plist-put session :monitoring-p nil))

    ;; Open chat
    (require 'orchid-chat)
    (let ((chat-buffer (orchid-chat-open session-id)))
      (plist-put session :chat-buffer chat-buffer)
      (plist-put session :log-buffer (orchid-log-get-buffer session-id))
      (plist-put session :monitoring-p t)
      chat-buffer)))

(defun orchid-session-close (session-id)
  "Close chat and stop monitoring for SESSION-ID."
  (when-let ((session (orchid-session-get session-id)))
    (when-let ((chat-buffer (plist-get session :chat-buffer)))
      (when (buffer-live-p chat-buffer)
        (kill-buffer chat-buffer))
      (plist-put session :chat-buffer nil))

    (when (plist-get session :monitoring-p)
      (require 'orchid-log)
      (orchid-log-stop-monitoring session-id)
      (plist-put session :log-buffer nil)
      (plist-put session :monitoring-p nil))))

(defun orchid-session-cleanup ()
  "Clean up dead buffers from registry."
  (dolist (entry orchid-session--registry)
    (let ((session (cdr entry)))
      (when-let ((chat-buffer (plist-get session :chat-buffer)))
        (unless (buffer-live-p chat-buffer)
          (plist-put session :chat-buffer nil)))

      (when-let ((log-buffer (plist-get session :log-buffer)))
        (unless (buffer-live-p log-buffer)
          (plist-put session :log-buffer nil)
          (plist-put session :monitoring-p nil))))))

;; Run cleanup periodically (every 5 minutes)
(run-with-idle-timer 300 t #'orchid-session-cleanup)

(provide 'session/orchid-session)

;;; orchid-session.el ends here
