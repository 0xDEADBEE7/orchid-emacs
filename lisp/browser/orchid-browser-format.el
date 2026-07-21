;;; orchid-browser-format.el --- Formatting utilities for session browser -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Formatting and display utilities for Orchid session browser.
;; Provides functions to format session data for display in the browser.

;;; Code:

(declare-function parse-iso8601-time-string "time-date" (date-string))
(declare-function orchid-session-browser--get-session-status "browser/orchid-browser-populate" (session))

(defun orchid-browser-format-file-size (bytes)
  "Format BYTES as human-readable file size.
Returns strings like \"1.5 MB\", \"234 KB\", etc.
Returns \"N/A\" if BYTES is nil."
  (if (null bytes)
      "N/A"
    (cond
     ((< bytes 1024)
      (format "%d B" bytes))
     ((< bytes (* 1024 1024))
      (format "%.1f KB" (/ bytes 1024.0)))
     ((< bytes (* 1024 1024 1024))
      (format "%.1f MB" (/ bytes 1024.0 1024.0)))
     (t
      (format "%.2f GB" (/ bytes 1024.0 1024.0 1024.0))))))

(defun orchid-browser-format-log-file-size (session-id)
  "Get file size of conversation log for SESSION-ID in bytes.
Returns nil if not found."
  (condition-case nil
      (let ((path (orchid-core-session-conversation-path session-id)))
        (when (file-exists-p path)
          (nth 7 (file-attributes path))))
    (error nil)))

;;; Relative-time cache
;;
;; Relative-time strings change at most once per minute.  Cache them keyed by
;; the ISO timestamp string and the current minute, so the expensive
;; parse-iso8601-time-string call only fires when the minute ticks over.

(defvar orchid-browser--relative-time-cache (make-hash-table :test 'equal)
  "Cache: (timestamp . minute-of-day) -> relative-time string.")

(defun orchid-browser-format-relative-time (iso-timestamp)
  "Format ISO-TIMESTAMP as a relative time string like \"5 minutes ago\".
Returns \"N/A\" if timestamp is nil or invalid."
  (if (or (null iso-timestamp) (string-empty-p iso-timestamp))
      "N/A"
    (let* ((now (current-time))
           (minute (floor (float-time now) 60))
           (key (cons iso-timestamp minute))
           (cached (gethash key orchid-browser--relative-time-cache)))
      (or cached
          (let ((result
                 (condition-case nil
                     (let* ((parsed-time (parse-iso8601-time-string iso-timestamp))
                            (delta (floor (float-time (time-subtract now parsed-time)))))
                       (cond
                        ((< delta 60)    "just now")
                        ((< delta 3600)  (let ((m (/ delta 60)))
                                           (format "%d minute%s ago" m (if (= m 1) "" "s"))))
                        ((< delta 86400) (let ((h (/ delta 3600)))
                                           (format "%d hour%s ago" h (if (= h 1) "" "s"))))
                        (t               (let ((d (/ delta 86400)))
                                           (format "%d day%s ago" d (if (= d 1) "" "s"))))))
                   (error "N/A"))))
            (puthash key result orchid-browser--relative-time-cache)
            result)))))

(defun orchid-browser-format-policy (session)
  "Get policy name from SESSION, or the default marker."
  (or (plist-get session :policy) "default"))

(defun orchid-browser-format-workspace-name (session)
  "Extract workspace directory name from SESSION working_dir path.
Returns the final directory component, or \"N/A\" if no working_dir."
  (if-let ((workspace (plist-get session :working_dir)))
      (file-name-nondirectory (directory-file-name workspace))
    "N/A"))

(defun orchid-browser-format-label (session)
  "Return display label for SESSION.
Uses :label if present; otherwise builds <persona>-<workspace-dir>;
falls back to :id."
  (or (plist-get session :label)
      (let ((policy (plist-get session :policy))
            (workspace-dir (orchid-browser-format-workspace-name session)))
        (when (and policy (not (equal workspace-dir "N/A")))
          (concat policy "-" workspace-dir)))
      (plist-get session :id)
      "unknown"))

(defun orchid-browser-format-status (status)
  "Format STATUS as display string.
STATUS can be a symbol (\\='active or \\='idle) or a plist with
:buffer and :process-running keys."
  (if (listp status)
      (let ((buffer-status (plist-get status :buffer))
            (process-running (plist-get status :process-running)))
        (cond
         ((and (eq buffer-status 'active) process-running) "ACTIVE•RUN")
         ((eq buffer-status 'active)                        "ACTIVE")
         (process-running                                    "IDLE•RUN")
         (t                                                  "IDLE")))
    (pcase status
      ('active "ACTIVE")
      (_ "IDLE"))))

(defun orchid-browser-format-entry-line (entry marked-sessions active-face idle-face)
  "Format ENTRY (session) as a table row.
MARKED-SESSIONS is hash table of marked session IDs.
ACTIVE-FACE and IDLE-FACE are faces to use for status display.
Returns formatted string with columns: LABEL, STATUS, UPDATED."
  (let* ((session-id (plist-get entry :id))
         (mark-type (and marked-sessions
                        (gethash session-id marked-sessions)))
         (label (orchid-browser-format-label entry))
         (updated (orchid-browser-format-relative-time (plist-get entry :updated_at)))
         (status (orchid-session-browser--get-session-status entry))
         (status-str (cond
                      ((eq mark-type 'delete) "DEL")
                      ((eq mark-type 'kill)   "KILL")
                      (t (orchid-browser-format-status status))))
         (status-face (cond
                       ((eq mark-type 'delete) 'error)
                       ((eq mark-type 'kill)   'warning)
                       (t (let ((buffer-status (if (listp status)
                                                   (plist-get status :buffer)
                                                 status)))
                            (if (eq buffer-status 'active)
                                active-face
                              idle-face)))))
         (row-face (cond
                    ((eq mark-type 'delete) 'error)
                    ((eq mark-type 'kill)   'warning)
                    (t nil))))
    (format "%-30s  %-10s %s"
            (propertize (truncate-string-to-width label 30 nil nil t)
                        'face (or row-face 'default))
            (propertize status-str 'face status-face)
            (propertize (truncate-string-to-width updated 18 nil nil t)
                        'face (or row-face 'shadow)))))

(provide 'browser/orchid-browser-format)

;;; orchid-browser-format.el ends here
