;;; orchid-core.el --- CLI wrapper for Orchid -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (json "1.4"))
;; Keywords: tools, processes
;; URL: https://github.com/yourusername/orchid

;;; Commentary:

;; This module provides functions to interact with the `orchid` CLI tool.
;; It handles both synchronous and asynchronous command execution, JSON parsing,
;; and error handling.

;;; Code:

(require 'json)

;;; Customization

(defgroup orchid-core nil
  "Orchid CLI wrapper."
  :group 'orchid
  :prefix "orchid-core-")

(defcustom orchid-core-cli-path "orchid"
  "Path to orchid CLI executable."
  :type 'string
  :group 'orchid-core)

(defcustom orchid-core-default-timeout 300
  "Default timeout in seconds for CLI commands."
  :type 'number
  :group 'orchid-core)

;;; Private Functions

(defun orchid-core--parse-json (output)
  "Parse JSON from OUTPUT, return elisp structure.
Returns the original output if parsing fails."
  (condition-case nil
      (let ((json-object-type 'plist)
            (json-array-type 'list)
            (json-key-type 'keyword))
        (json-read-from-string output))
    (error output)))

(defun orchid-core--extract-error (output)
  "Extract error message from OUTPUT.
Tries to parse as JSON first, otherwise returns raw output."
  (or
   (condition-case nil
       (let* ((json-object-type 'plist)
              (data (json-read-from-string output)))
         (plist-get data :error))
     (error nil))
   output))

(defun orchid-core--make-result (exit-code output duration)
  "Create result plist from EXIT-CODE, OUTPUT, and DURATION."
  (if (and (integerp exit-code) (zerop exit-code))
      (list :success t
            :data (orchid-core--parse-json output)
            :raw output
            :exit-code exit-code
            :duration duration)
    (list :success nil
          :error (orchid-core--extract-error output)
          :raw output
          :exit-code exit-code
          :duration duration)))

(defun orchid-core--execute (args &optional callback)
  "Execute orchid CLI with ARGS.
If CALLBACK provided, execute async; otherwise sync."
  (unless (orchid-core-cli-available-p)
    (error "Orchid CLI not found.  Install it or set `orchid-core-cli-path'"))
  (if callback
      (orchid-core--execute-internal-async args callback)
    (orchid-core--execute-internal-sync args)))

(defun orchid-core--execute-internal-sync (args)
  "Execute ARGS synchronously, return result plist."
  (let* ((start-time (current-time))
         (output-buffer (generate-new-buffer " *orchid-output*"))
         (exit-code (apply #'call-process
                           orchid-core-cli-path
                           nil
                           output-buffer
                           nil
                           args))
         (output (with-current-buffer output-buffer (buffer-string)))
         (duration (float-time (time-subtract (current-time) start-time))))
    (kill-buffer output-buffer)
    (orchid-core--make-result exit-code output duration)))

(defun orchid-core--execute-internal-async (args callback)
  "Execute ARGS asynchronously, call CALLBACK with result.
Returns the process object."
  (let ((start-time (current-time))
        (output-buffer (generate-new-buffer " *orchid-output*")))
    (make-process
     :name "orchid-cli"
     :buffer output-buffer
     :command (cons orchid-core-cli-path args)
     :sentinel
     (lambda (proc _event)
       (when (memq (process-status proc) '(exit signal))
         (let* ((exit-code (process-exit-status proc))
                (output (with-current-buffer output-buffer (buffer-string)))
                (duration (float-time (time-subtract (current-time) start-time))))
           (kill-buffer output-buffer)
           (when callback
             (funcall callback (orchid-core--make-result exit-code output duration)))))))))

;;; Public API

(defun orchid-core-cli-available-p ()
  "Check if orchid CLI is available."
  (executable-find orchid-core-cli-path))

(defun orchid-core-get-version (&optional callback)
  "Get orchid CLI version.
Async if CALLBACK provided, otherwise sync."
  (orchid-core--execute '("--version") callback))

(defun orchid-core-create (&rest args)
  "Create a new conversation without sending a message.
ARGS: :label, :profile, :callback.
Returns metadata JSON with :id on success.
To set persona or working-dir, call `orchid-core-set' after creation."
  (let* ((label (plist-get args :label))
         (profile (plist-get args :profile))
         (callback (plist-get args :callback))
         (cmd-args (list "create")))
    (when label
      (setq cmd-args (append cmd-args (list "--label" label))))
    (when profile
      (setq cmd-args (append cmd-args (list "--profile" profile))))
    (orchid-core--execute cmd-args callback)))

(defun orchid-core-send (message &optional conversation-id &rest args)
  "Send MESSAGE to CONVERSATION-ID.
ARGS: :await, :profile, :callback.
If CONVERSATION-ID is nil, starts a new conversation."
  (let* ((await (plist-get args :await))
         (profile (plist-get args :profile))
         (callback (plist-get args :callback))
         (cmd-args (list "send")))
    (when conversation-id
      (setq cmd-args (append cmd-args (list "--id" conversation-id))))
    (when await
      (setq cmd-args (append cmd-args '("--await"))))
    (when profile
      (setq cmd-args (append cmd-args (list "--profile" profile))))
    ;; message must come last — positional arg after all flags
    (setq cmd-args (append cmd-args (list message)))
    (orchid-core--execute cmd-args callback)))

(defun orchid-core-set (conversation-id &rest args)
  "Set properties on CONVERSATION-ID.
ARGS: :label, :working-dir, :persona, :profile, :callback."
  (let* ((label (plist-get args :label))
         (working-dir (plist-get args :working-dir))
         (persona (plist-get args :persona))
         (profile (plist-get args :profile))
         (callback (plist-get args :callback))
         (cmd-args (list "set" "--id" conversation-id)))
    (when label
      (setq cmd-args (append cmd-args (list "--label" label))))
    (when working-dir
      (setq cmd-args (append cmd-args (list "--working-dir" working-dir))))
    (when persona
      (setq cmd-args (append cmd-args (list "--persona" persona))))
    (when profile
      (setq cmd-args (append cmd-args (list "--profile" profile))))
    (orchid-core--execute cmd-args callback)))

(defun orchid-core-stop (conversation-id &optional callback)
  "Stop the running tool loop for CONVERSATION-ID.
Calls `orchid stop <id>` (SIGTERM)."
  (orchid-core--execute (list "stop" conversation-id) callback))

(defun orchid-core-delete (conversation-id &optional callback)
  "Permanently delete CONVERSATION-ID.
Async if CALLBACK provided, otherwise sync."
  (orchid-core--execute (list "delete" conversation-id) callback))

(defun orchid-core-list (&optional callback)
  "List all conversations.  Async if CALLBACK provided.
Returns a JSON array of conversation metadata objects."
  (orchid-core--execute '("list") callback))

(defun orchid-core-config-current (&optional callback)
  "Get the active config profile.  Async if CALLBACK provided."
  (orchid-core--execute '("config" "current") callback))

(provide 'core/orchid-core)

;;; orchid-core.el ends here
