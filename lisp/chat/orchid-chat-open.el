;;; orchid-chat-open.el --- Session open commands for Orchid chat -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Public constructors for Orchid chat buffers: orchid-chat-open and
;; orchid-chat-open-new.  Extracted from orchid-chat-session.el to keep
;; that module within the 200-line target.

;;; Code:

(require 'core/orchid-core)
(require 'log/orchid-logging)
(require 'log/orchid-log-restore)

;; Private helpers defined in chat/orchid-chat-session
(declare-function orchid-chat--initialize-buffer "chat/orchid-chat-session" (session-id))
(declare-function orchid-chat--setup-history-cursor "chat/orchid-chat-session" ())
(declare-function orchid-chat--restore-session-history "chat/orchid-chat-session" (session-id buffer))
(declare-function orchid-chat--finalize-history-display "chat/orchid-chat-session" (event-count process-running))
(declare-function orchid-chat--setup-process-indicator "chat/orchid-chat-session" (session-id &optional run-started-str))
(declare-function orchid-chat--start-log-monitoring "chat/orchid-chat-session" (session-id buffer))
(declare-function orchid-chat--setup-buffer "orchid-chat" (session-id label))
(declare-function orchid-chat-mode "orchid-chat" ())
(declare-function orchid-chat--insert-more-button "orchid-chat" ())
(declare-function orchid-chat--cleanup "chat/orchid-chat-session" ())
(declare-function orchid-session--read-metadata "orchid-session" (session-id))
(declare-function orchid-chat-insert-system-message "orchid-chat" (msg))
(declare-function orchid-session-register "session/orchid-session" (session))

;; Customization variable defined in orchid-log.el
(defvar orchid-log-restore-max-events)

;; Buffer-local variables declared in orchid-chat.el
(defvar orchid-chat--session-id)
(defvar orchid-chat--history-cursor)
(defvar orchid-chat--input-marker)
(defvar orchid-chat--loaded-event-ids)

(defun orchid-chat-open (session-id)
  "Open chat buffer for SESSION-ID."
  (let* ((start-time (current-time))
         (metadata (orchid-session--read-metadata session-id))
         (process-running (equal (plist-get metadata :status) "running"))
         (run-started-str (plist-get metadata :run_started_at))
         (chat-buffer (orchid-chat--initialize-buffer session-id)))

    (orchid-log "PERF: Session open started for %s" session-id)

    (with-current-buffer chat-buffer
      (condition-case err
          (progn
            ;; Set up history cursor and [More] button
            (orchid-chat--setup-history-cursor)
            (when orchid-log-restore-max-events
              (save-excursion
                (goto-char orchid-chat--history-cursor)
                (orchid-chat--insert-more-button)))

            ;; Restore session history
            (let* ((restore-start (current-time))
                   (result (orchid-chat--restore-session-history session-id chat-buffer))
                   (count (plist-get result :count))
                   (seen-events (plist-get result :seen-events)))

              (orchid-log "PERF: Restore completed %d events in %.3fs"
                         count
                         (float-time (time-subtract (current-time) restore-start)))

              ;; Store loaded event IDs for incremental loading
              (setq orchid-chat--loaded-event-ids seen-events)

              ;; Finalize history display
              (orchid-chat--finalize-history-display count process-running)

              ;; Set up process indicator if needed
              (when process-running
                (orchid-chat--setup-process-indicator session-id run-started-str))))

        (error
         (orchid-log "Failed to restore session history: %S" err)))

      ;; Start log monitoring
      (let ((monitor-start (current-time)))
        (orchid-chat--start-log-monitoring session-id chat-buffer)
        (orchid-log "PERF: Monitoring started in %.3fs"
                   (float-time (time-subtract (current-time) monitor-start)))))

    ;; Switch to buffer and position cursor
    (switch-to-buffer chat-buffer)
    (goto-char (point-max))
    (orchid-log "PERF: Total session open time: %.3fs"
               (float-time (time-subtract (current-time) start-time)))
    chat-buffer))

(defun orchid-chat-open-new (&optional policy prompt)
  "Open chat buffer for a new session with optional POLICY and PROMPT."
  (let* ((full-dir (expand-file-name default-directory))
         (workspace-name (file-name-nondirectory (directory-file-name full-dir)))
         (policy-str (or policy "default"))
         (buffer (generate-new-buffer
                  (format "*orchid-chat-%s-%s-new*"
                          (downcase policy-str) (downcase workspace-name)))))
    (orchid-log "[open-new] policy=%S prompt=%S workspace=%S" policy prompt full-dir)
    (with-current-buffer buffer
      (orchid-chat-mode)
      (orchid-chat--setup-buffer "pending" "pending")
      (add-hook 'kill-buffer-hook #'orchid-chat--cleanup nil t))
    (switch-to-buffer buffer)
    (goto-char (point-max))
    (orchid-core-create
     :working-dir full-dir :policy policy :prompt prompt
     :callback
     (lambda (create-result)
       (if (not (plist-get create-result :success))
           (when (buffer-live-p buffer)
             (with-current-buffer buffer
               (orchid-chat-insert-system-message
                (format "Failed to create session:\n%s"
                        (or (plist-get create-result :error)
                            (plist-get create-result :raw))))))
         (let* ((session-data (plist-get create-result :data))
                (session-id (plist-get session-data :id)))
           (orchid-log "[open-new] created %s" session-id)
           (when (buffer-live-p buffer)
             (with-current-buffer buffer
               (orchid-chat--open-new-activate
                session-id buffer workspace-name policy prompt)))))))
    buffer))

(defun orchid-chat--open-new-activate (session-id buffer workspace-name policy _prompt)
  "Activate a freshly created SESSION-ID in BUFFER."
  (require 'session/orchid-session)
  (require 'orchid-log)
  (let* ((session (orchid-session--read-metadata session-id))
         (policy-name (or policy (plist-get session :policy)))
         (label (when workspace-name
                  (if policy-name
                      (format "%s-%s" (downcase policy-name) workspace-name)
                    workspace-name))))
    (orchid-session-register session)
    (setq orchid-chat--session-id session-id)
    ;; Rebuild buffer header with real session data
    (orchid-chat--setup-buffer session-id session-id)
    (rename-buffer
     (format "*orchid-chat-%s-%s-%s*"
             (downcase (or policy "default"))
             (downcase workspace-name)
             (substring session-id (max 0 (- (length session-id) 5))))
     t)
    (when label
      (orchid-core-set session-id :label label :callback #'ignore))
    (orchid-log "[open-new] activated session %s label=%S" session-id label)))

(provide 'chat/orchid-chat-open)

;;; orchid-chat-open.el ends here
