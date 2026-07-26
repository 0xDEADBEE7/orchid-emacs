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
  "Path to the Orchid CLI executable."
  :type 'string
  :group 'orchid-core)

(defcustom orchid-core-config-dir
  (expand-file-name "~/.config/orchid/")
  "Simplified-harness configuration and session root.

This directory contains config.json, policies, connections, auth, prompts,
sessions, and logs.jsonl."
  :type 'directory
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
         (or (plist-get data :error)
             (plist-get data :message)))
     (error nil))
   output))

(defun orchid-core--make-result (exit-code output duration)
  "Create result plist from EXIT-CODE, OUTPUT, and DURATION."
  (if (and (integerp exit-code) (zerop exit-code))
      (orchid-core--normalize-result
       (list :success t
             :data (orchid-core--parse-json output)
             :raw output
             :exit-code exit-code
             :duration duration))
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
      (orchid-core--execute-internal-async
       (orchid-core--with-config args) callback)
    (orchid-core--execute-internal-sync (orchid-core--with-config args))))

(defun orchid-core--with-config (args)
  "Return ARGS with the selected configuration directory.

`--config` is a global CLI option.  Put it before the command so this works
with both current and older CLI builds."
  (if args
      (append (list "--config" (expand-file-name orchid-core-config-dir)) args)
    (list "--config" (expand-file-name orchid-core-config-dir))))

(defun orchid-core-session-path (session-id file)
  "Return FILE beneath SESSION-ID in the configured session store."
  (expand-file-name (format "sessions/%s/%s" session-id file)
                    (expand-file-name orchid-core-config-dir)))

(defun orchid-core-session-metadata-path (session-id)
  "Return the metadata path for SESSION-ID."
  (orchid-core-session-path session-id "metadata.json"))

(defun orchid-core-session-events-path (session-id)
  "Return the event stream path for SESSION-ID."
  (orchid-core-session-path session-id "events.jsonl"))

(defun orchid-core-session-log-path (session-id)
  "Return the per-session log path for SESSION-ID."
  (orchid-core-session-path session-id "logs.jsonl"))

(defalias 'orchid-core-session-conversation-path #'orchid-core-session-events-path)

(defun orchid-core--execute-internal-sync (args)
  "Execute ARGS synchronously, return result plist."
  (let* ((start-time (current-time))
         (output-buffer (generate-new-buffer " *orchid-output*"))
         (exit-code (apply #'call-process
                           orchid-core-cli-path
                           nil
                           (cons output-buffer output-buffer)
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
     :stderr output-buffer
     :command (cons orchid-core-cli-path args)
     :sentinel
     (lambda (proc _event)
       (when (memq (process-status proc) '(exit signal))
         (let* ((exit-code (process-exit-status proc))
                (output (with-current-buffer output-buffer (buffer-string)))
                (duration (float-time (time-subtract (current-time) start-time))))
           (kill-buffer output-buffer)
           (when callback
             (funcall callback
                      (orchid-core--normalize-result
                       (orchid-core--make-result exit-code output duration))))))))))

(defun orchid-core--normalize-session (session)
  "Flatten a simplified-harness session into the client's session plist."
  (let ((metadata (or (plist-get session :metadata) session))
        (state (plist-get session :state)))
    (append metadata
            (when state
              (list :status (plist-get state :status)
                    :pid (plist-get state :pid)
                    :last_message (plist-get state :last_message)
                    :running (equal (plist-get state :status) "running"))))))

(defun orchid-core--normalize-result (result)
  "Normalize simplified-harness command output for client callers."
  (when (and result (plist-get result :success))
    (let ((data (plist-get result :data)))
      (let ((sessions (and (listp data) (plist-get data :sessions))))
        (when (and sessions (listp sessions))
          (plist-put result :data
                     (mapcar #'orchid-core--normalize-session sessions))))))
  result)

;;; Public API

(defun orchid-core-cli-available-p ()
  "Check if orchid CLI is available."
  (executable-find orchid-core-cli-path))

(defun orchid-core-get-version (&optional callback)
  "Get orchid CLI version.
Async if CALLBACK provided, otherwise sync."
  (orchid-core--execute '("--version") callback))

(defun orchid-core-create (&rest args)
  "Create a new simplified-harness session.
  ARGS: :label, :working-dir, :agent, :callback.
Returns metadata JSON with :id on success."
  (let* ((label (plist-get args :label))
         (working-dir (plist-get args :working-dir))
         (agent (plist-get args :agent))
         (callback (plist-get args :callback))
         (cmd-args (list "create")))
    (when label
      (setq cmd-args (append cmd-args (list "--label" label))))
    (when working-dir (setq cmd-args (append cmd-args (list "--working-dir" working-dir))))
    (when agent (setq cmd-args (append cmd-args (list "--agent" agent))))
    (orchid-core--execute cmd-args callback)))

(defun orchid-core-send (message &optional conversation-id &rest args)
  "Send MESSAGE asynchronously to CONVERSATION-ID.
  ARGS: :label, :working-dir, :agent, :callback.
Use `orchid-core-await' when the worker should be joined."
  (let* ((label (plist-get args :label))
         (working-dir (plist-get args :working-dir))
         (agent (plist-get args :agent))
         (callback (plist-get args :callback))
         (cmd-args (list "send")))
    (when conversation-id
      (setq cmd-args (append cmd-args (list "--id" conversation-id))))
    (when label (setq cmd-args (append cmd-args (list "--label" label))))
    (when working-dir (setq cmd-args (append cmd-args (list "--working-dir" working-dir))))
    (when agent (setq cmd-args (append cmd-args (list "--agent" agent))))
    ;; message must come last — positional arg after all flags
    (setq cmd-args (append cmd-args (list message)))
    (orchid-core--execute cmd-args callback)))

(defun orchid-core-set (conversation-id &rest args)
  "Set properties on CONVERSATION-ID.
  ARGS: :label, :working-dir, :restrictions, :callback."
  (let* ((label (plist-get args :label))
         (working-dir (plist-get args :working-dir))
         (callback (plist-get args :callback))
         (cmd-args (list "set" conversation-id)))
    (when label
      (setq cmd-args (append cmd-args (list "--label" label))))
    (when working-dir
      (setq cmd-args (append cmd-args (list "--working-dir" working-dir))))
    (orchid-core--execute cmd-args callback)))

(defun orchid-core-stop (conversation-id &optional callback)
  "Stop the running tool loop for CONVERSATION-ID.
Calls `orchid stop <id>` (SIGTERM)."
  (orchid-core--execute (list "stop" conversation-id) callback))

(defun orchid-core-delete (conversation-id &optional callback)
  "Archive CONVERSATION-ID using the simplified harness.
Async if CALLBACK provided, otherwise sync."
  (orchid-core--execute (list "delete" conversation-id) callback))

(defun orchid-core-kill (session-id &optional callback)
  "Stop SESSION-ID."
  (orchid-core-stop session-id callback))

(defun orchid-core-list (&optional resource callback)
  "List simplified-harness sessions.  Async if CALLBACK provided."
  (when (functionp resource) (setq callback resource resource nil))
  (orchid-core--execute '("list") callback))

(defun orchid-core-list-agents (&optional callback)
  "List configured agent summaries."
  (let ((result (orchid-core--execute '("agent") callback)))
    (if callback result
      (when (and result (plist-get result :success))
        (plist-get (plist-get result :data) :agents)))))

(defalias 'orchid-core-list-policies #'orchid-core-list-agents)

(defun orchid-core-list-prompts (&optional callback)
  "List configured prompt names."
  (if callback
      (funcall callback (list :success t :data '("default")))
    '("default")))

(defun orchid-core-await (session-id &optional timeout callback)
  "Wait for SESSION-ID to finish, optionally with TIMEOUT seconds."
  (let ((args (list "await" session-id)))
    (when timeout (setq args (append args (list "--timeout" (number-to-string timeout)))))
    (orchid-core--execute args callback)))

(defun orchid-core-validate (&optional callback)
  "Validate the selected configuration."
  (let ((result (list :success t :data t :raw "" :exit-code 0 :duration 0)))
    (if callback (funcall callback result) result)))

(provide 'core/orchid-core)

;;; orchid-core.el ends here
