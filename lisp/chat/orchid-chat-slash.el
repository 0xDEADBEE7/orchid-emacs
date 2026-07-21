;;; orchid-chat-slash.el --- Slash-command menu for Orchid chat -*- lexical-binding: t -*-

;;; Commentary:
;; Triggered when user types "/" at the start of the input area.
;; Defers via run-at-time, then presents commands via completing-read.

;;; Code:

(require 'cl-lib)
(require 'chat/orchid-chat-config)
(require 'core/orchid-faces)
(require 'core/orchid-core)
(require 'session/orchid-session)

(declare-function orchid-chat-open-new "chat/orchid-chat-open" ())
(declare-function orchid-chat--cleanup "chat/orchid-chat-session" ())
(declare-function orchid-core-stop "core/orchid-core" (conversation-id &optional callback))
(declare-function orchid-session-get "session/orchid-session" (session-id))
(defvar orchid-chat--session-id)
(defvar orchid-chat--input-marker)

;;; Command registry

(defvar orchid-chat-slash--commands
  '(("metadata"     . orchid-chat-slash--cmd-metadata)
    ("config"       . orchid-chat-slash--cmd-config)
    ("kill"         . orchid-chat-slash--cmd-kill)
    ("logs"         . orchid-chat-slash--cmd-logs)
    ("new"          . orchid-chat-slash--cmd-new)
    ("clear"        . orchid-chat-slash--cmd-new)
    ("scope-escape" . orchid-chat-slash--cmd-scope-escape)
    ("quit"         . orchid-chat-slash--cmd-quit)
    ("exit"         . orchid-chat-slash--cmd-quit))
  "Alist of slash command name -> handler function.")

;;; Entry point

(defun orchid-chat-slash-maybe-open ()
  "Open slash-command menu when user types \"/\" at start of input line."
  (when (and orchid-chat--input-marker
             (>= (point) (marker-position orchid-chat--input-marker)))
    (let* ((line-start (save-excursion (beginning-of-line) (point)))
           (text       (buffer-substring-no-properties line-start (point))))
      (when (string-equal text "/")
        (let ((buf (current-buffer)))
          (run-at-time 0 nil #'orchid-chat-slash--prompt buf))))))

(defun orchid-chat-slash--prompt (chat-buf)
  "Present slash-command menu for CHAT-BUF via completing-read."
  (when (buffer-live-p chat-buf)
    (with-current-buffer chat-buf
      (orchid-chat--clear-slash-input))
    (let* ((candidates (orchid-chat-slash--candidate-alist))
           (names      (mapcar #'car candidates))
           (choice     (condition-case _
                           (completing-read "/ " names nil t)
                         (quit nil))))
      (when choice
        (when-let ((fn (cdr (assoc choice candidates))))
          (with-current-buffer chat-buf
            (funcall fn)))))))

(defun orchid-chat-slash--candidate-alist ()
  "Return deduped alist of display-name -> fn for completing-read."
  (let ((fn-to-names (make-hash-table :test 'eq))
        result)
    (dolist (pair orchid-chat-slash--commands)
      (puthash (cdr pair)
               (cons (car pair) (gethash (cdr pair) fn-to-names nil))
               fn-to-names))
    (maphash
     (lambda (fn names)
       (let* ((sorted  (sort (copy-sequence names)
                             (lambda (a b) (< (length a) (length b)))))
              (canon   (car sorted))
              (aliases (cdr sorted))
              (label   (if aliases
                           (format "%s  (%s)" canon
                                   (mapconcat #'identity aliases ", "))
                         canon)))
         (push (cons label fn) result)))
     fn-to-names)
    (sort result (lambda (a b) (string< (car a) (car b))))))

(defun orchid-chat--clear-slash-input ()
  "Remove the /query text typed in the chat buffer input area."
  (let ((input-start (or (and (markerp orchid-chat--input-marker)
                              (marker-position orchid-chat--input-marker))
                         (point-min))))
    (save-excursion
      (goto-char (point-max))
      (let ((line-start (save-excursion (beginning-of-line) (point))))
        (when (>= line-start input-start)
          (let ((inhibit-read-only t))
            (delete-region line-start (point-max))))))))

;;; Command implementations

(defun orchid-chat-slash--cmd-metadata ()
  "Open metadata.json for the current session."
  (when orchid-chat--session-id
    (find-file
     (orchid-core-session-metadata-path orchid-chat--session-id))))

(defun orchid-chat-slash--cmd-config ()
  "Open the selected Orchid configuration directory."
  (dired (expand-file-name orchid-core-config-dir)))

(defun orchid-chat-slash--cmd-logs ()
  "Open orchid.log for the current session."
  (when orchid-chat--session-id
    (find-file
     (expand-file-name "orchid.log" orchid-core-config-dir))))

(defun orchid-chat-slash--cmd-kill ()
  "Stop the running process for the current session."
  (when orchid-chat--session-id
    (orchid-core-stop orchid-chat--session-id
                      (lambda (result)
                        (message "[orchid] kill: %s"
                                 (if (plist-get result :success)
                                     "stopped"
                                   (or (plist-get result :error) "failed")))))))

(defun orchid-chat-slash--cmd-new ()
  "Open a new session with the same settings as the current session."
  (require 'chat/orchid-chat-open)
  (let* ((session (when orchid-chat--session-id
                    (orchid-session-get orchid-chat--session-id)))
         (policy     (when session (plist-get session :policy)))
         (workdir    (when session (or (plist-get session :working_dir)
                                       (plist-get session :workspace)))))
    (let ((default-directory (or workdir default-directory)))
      (orchid-chat-open-new policy (plist-get session :prompt)))))

(defun orchid-chat-slash--cmd-scope-escape ()
  "Toggle allow_scope_escape in metadata.json for the current session."
  (when orchid-chat--session-id
    (let* ((path (orchid-core-session-metadata-path orchid-chat--session-id))
           (meta (when (file-exists-p path)
                   (condition-case nil
                       (with-temp-buffer
                         (insert-file-contents path)
                         (if (fboundp 'json-parse-buffer)
                             (json-parse-buffer :object-type 'plist :array-type 'list)
                           (let ((json-object-type 'plist)
                                 (json-array-type  'list)
                                 (json-key-type    'keyword))
                             (json-read))))
                     (error nil))))
           (current (plist-get meta :allow_scope_escape))
           (new-val (not (eq current t))))
      (plist-put meta :allow_scope_escape (if new-val t :false))
      (with-temp-file path
        (if (fboundp 'json-insert)
            (json-insert meta)
          (insert (json-encode meta))))
      (message "[orchid] allow_scope_escape: %s" (if new-val "enabled" "disabled")))))

(defun orchid-chat-slash--cmd-quit ()
  "Close the chat buffer."
  (kill-buffer (current-buffer)))

(provide 'chat/orchid-chat-slash)

;;; orchid-chat-slash.el ends here
