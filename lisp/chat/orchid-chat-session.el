;;; orchid-chat-session.el --- Session lifecycle management for Orchid chat -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Handles session creation, monitoring startup, and session lifecycle
;; management for the Orchid chat interface.

;;; Code:

(require 'core/orchid-core)
(require 'session/orchid-session)
(require 'orchid-log)
(require 'core/orchid-faces)
(require 'core/orchid-processing-indicator)
(require 'core/orchid-socket-view)
(require 'log/orchid-logging)
(require 'chat/orchid-chat-config)

;; Forward declarations for chat functions
(declare-function orchid-chat-mode "orchid-chat")
(declare-function orchid-chat--setup-buffer "orchid-chat")
(declare-function orchid-chat--init-assistant-cursor "orchid-chat")
(declare-function orchid-chat-insert-log-line "orchid-chat")
(declare-function orchid-chat--insert-more-button "orchid-chat")
(declare-function orchid-chat--remove-more-button "orchid-chat")
(declare-function orchid-session--read-metadata "session/orchid-session" (session-id))

;; Buffer-local variables declared in orchid-chat.el
(defvar orchid-chat--session-id)
(defvar orchid-chat--assistant-cursor)
(defvar orchid-chat--history-cursor)
(defvar orchid-chat--input-marker)
(defvar orchid-chat--loaded-event-ids)
(defvar orchid-socket-view--region-end)

(defun orchid-chat--format-buffer-name (session-id session)
  "Format buffer name for SESSION-ID with SESSION data.
Format: *orchid-chat-<persona>-<workspace-dir>-<last-5-digits>*
Uses only the last directory name of the workspace path."
  (let* ((persona (or (plist-get session :persona) "default"))
         (workspace-path (or (plist-get session :working_dir)
                             (plist-get session :workspace)
                             "none"))
         (workspace-dir (if (string= workspace-path "none")
                           "none"
                         (file-name-nondirectory
                          (directory-file-name workspace-path))))
         (hash-suffix (if (>= (length session-id) 5)
                         (substring session-id (- (length session-id) 5))
                       session-id)))
    (format "*orchid-chat-%s-%s-%s*"
            (downcase persona)
            (downcase workspace-dir)
            hash-suffix)))

(defun orchid-chat--format-header-metadata (session-id &optional session)
  "Format metadata section for SESSION-ID.
Uses SESSION plist if provided, otherwise fetches from registry.
Returns formatted string with workspace, persona, and open-logs button."
  (let* ((s (or session (orchid-session-get session-id)))
         (persona (or (plist-get s :persona) "default"))
         (workspace (or (plist-get s :working_dir)
                        (plist-get s :workspace)
                        "N/A"))
         (meta-path (expand-file-name
                     (format "~/.config/orchid/conversations/%s/metadata.json"
                             session-id)))
         (config-path (expand-file-name "~/.config/orchid/config.json"))
         (meta-button (propertize "[META]"
                                  'face 'orchid-button
                                  'mouse-face 'highlight
                                  'help-echo meta-path
                                  'keymap (let ((map (make-sparse-keymap)))
                                            (define-key map (kbd "RET")
                                              (lambda () (interactive)
                                                (find-file meta-path)))
                                            (define-key map [mouse-1]
                                              (lambda () (interactive)
                                                (find-file meta-path)))
                                            map)
                                  'rear-nonsticky t))
         (config-button (propertize "[CONFIG]"
                                    'face 'orchid-button
                                    'mouse-face 'highlight
                                    'help-echo config-path
                                    'keymap (let ((map (make-sparse-keymap)))
                                              (define-key map (kbd "RET")
                                                (lambda () (interactive)
                                                  (find-file config-path)))
                                              (define-key map [mouse-1]
                                                (lambda () (interactive)
                                                  (find-file config-path)))
                                              map)
                                    'rear-nonsticky t)))
    (format "Workspace: %s\nPersona: %s\n%s  %s\n"
            (propertize workspace 'face 'font-lock-string-face)
            (propertize persona 'face 'font-lock-keyword-face)
            meta-button
            config-button)))

(defun orchid-chat--cleanup ()
  "Clean up current chat buffer's resources."
  (when orchid-chat--session-id
    (orchid-processing-cleanup)
    (orchid-log-stop-monitoring orchid-chat--session-id)
    (when-let ((session (orchid-session-get orchid-chat--session-id)))
      (plist-put session :chat-buffer nil)
      (plist-put session :log-buffer nil)
      (plist-put session :monitoring-p nil))))

(defun orchid-chat--initialize-buffer (session-id)
  "Initialize chat buffer for SESSION-ID with mode and hooks.
Returns the created buffer."
  (let* ((session (orchid-session-get session-id))
         (buffer-name (orchid-chat--format-buffer-name session-id session))
         (buffer (get-buffer-create buffer-name)))
    (with-current-buffer buffer
      (orchid-chat-mode)
      (setq orchid-chat--session-id session-id)
      (orchid-chat--setup-buffer session-id session-id)
      (add-hook 'kill-buffer-hook #'orchid-chat--cleanup nil t))
    buffer))

(defun orchid-chat--setup-history-cursor ()
  "Set up history cursor marker in header section.
Positions cursor before separator where [More] button should appear."
  (goto-char (point-min))
  ;; Skip past the metadata header lines (Workspace, Persona, [META] [CONFIG])
  (when (re-search-forward "^\\[META\\]" nil t)
    (forward-line 1))
  (setq orchid-chat--history-cursor (point-marker))
  (set-marker-insertion-type orchid-chat--history-cursor t))

(defun orchid-chat--restore-session-history (session-id buffer)
  "Restore session history for SESSION-ID into BUFFER.
Returns plist with :count and :seen-events."
  (orchid-log-restore-session
   session-id
   (lambda (parsed-event)
     (orchid-chat-insert-log-line buffer parsed-event))))


(defun orchid-chat--session-restored-line ()
  "Return a propertized '[session restored]  <token-estimate>' line."
  (let* ((prefix "[session restored]")
         (token-str (when orchid-chat--session-id
                      (let* ((metadata (orchid-session--read-metadata orchid-chat--session-id))
                             (tokens (plist-get metadata :token_estimate)))
                        (when (and (integerp tokens) (> tokens 0))
                          (format "~%dk tokens" (/ tokens 1000))))))
         (padding (when token-str
                    (make-string (max 1 (- 80 (length prefix) (length token-str))) ?\s)))
         (line (concat prefix (or (and padding token-str (concat padding token-str)) "") "\n")))
    (propertize line 'face 'shadow 'read-only t 'rear-nonsticky t)))

(defun orchid-chat--finalize-history-display (event-count process-running)
  "Finalize history display after loading EVENT-COUNT events.
Handles [More] button removal, separator insertion, and markers.
PROCESS-RUNNING indicates if session has active process."
  (when (and orchid-log-restore-max-events (= event-count 0))
    (orchid-chat--remove-more-button))

  (when (> event-count 0)
    (goto-char (point-max))
    (insert "\n")
    (insert (orchid-chat--session-restored-line))
    (unless process-running
      (insert (propertize (orchid-chat--session-separator)
                         'face 'orchid-chat-separator-face
                         'read-only t
                         'rear-nonsticky t))
      (insert "\n")
      ;; orchid-socket-view-start uses save-excursion internally — point stays
      ;; at the pre-bar position.  Mirror orchid-chat--prepare-for-response:
      ;; insert the sentinel \n at region-end (after the bar) by temporarily
      ;; setting insertion-type nil, then use region-end as input-marker.
      (orchid-socket-view-start orchid-chat--session-id (point))
      (set-marker-insertion-type orchid-socket-view--region-end nil)
      (save-excursion
        (goto-char (marker-position orchid-socket-view--region-end))
        (insert "\n"))
      (set-marker-insertion-type orchid-socket-view--region-end t)
      (setq orchid-chat--input-marker orchid-socket-view--region-end)
      (orchid-chat--init-assistant-cursor
       (marker-position orchid-socket-view--region-end))
      (goto-char (point-max)))
    (when process-running
      (setq orchid-chat--input-marker (point-marker))
      (set-marker-insertion-type orchid-chat--input-marker nil)
      (orchid-chat--init-assistant-cursor (point)))))

(defun orchid-chat--setup-process-indicator (session-id &optional run-started-str)
  "Set up processing indicator for SESSION-ID.
RUN-STARTED-STR is an ISO-8601 timestamp string for the run start time."
  (orchid-log "Session %s has running process, showing indicator" session-id)
  (save-excursion
    (goto-char (point-max))
    (require 'orchid-processing-indicator)
    (let ((start-time (when run-started-str
                        (condition-case nil
                            (float-time (date-to-time run-started-str))
                          (error nil)))))
      (orchid-processing-show session-id start-time))
    (insert (propertize (orchid-chat--session-separator)
                       'face 'orchid-chat-separator-face
                       'read-only t
                       'rear-nonsticky t))
    (insert "\n")
    (setq orchid-chat--input-marker (point-marker))
    (set-marker-insertion-type orchid-chat--input-marker nil)
    ;; Socket view bar sits directly after the separator.
    (orchid-socket-view-start session-id (point))))

(defun orchid-chat--start-log-monitoring (session-id buffer)
  "Start log monitoring for SESSION-ID, inserting events into BUFFER."
  (orchid-log-start-monitoring
   session-id
   (lambda (parsed-event)
     (orchid-chat-insert-log-line buffer parsed-event))))

(require 'chat/orchid-chat-open)

(provide 'chat/orchid-chat-session)

;;; orchid-chat-session.el ends here
