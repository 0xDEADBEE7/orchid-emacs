;;; orchid-browser-marks.el --- Mark and execute operations for session browser -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Mark/unmark sessions for bulk deletion or process termination, and execute
;; all pending marked operations.

;;; Code:

(require 'cl-lib)
(require 'core/orchid-core)
(require 'session/orchid-session)

(declare-function orchid-session-browser--selected-session "browser/orchid-browser-populate")
(declare-function orchid-session-browser--populate "browser/orchid-browser-populate")
(declare-function orchid-session-browser-refresh "orchid-session-browser")

(defvar orchid-session-browser--marked-sessions)

(defun orchid-session-browser-mark-for-deletion ()
  "Mark selected session for deletion."
  (interactive)
  (when-let ((session (orchid-session-browser--selected-session)))
    (unless orchid-session-browser--marked-sessions
      (setq orchid-session-browser--marked-sessions (make-hash-table :test 'equal)))
    (puthash (plist-get session :id) 'delete orchid-session-browser--marked-sessions)
    (cl-incf orchid-session-browser--selected)
    (orchid-session-browser--populate)))

(defun orchid-session-browser-mark-for-kill ()
  "Mark selected session for process kill."
  (interactive)
  (when-let ((session (orchid-session-browser--selected-session)))
    (let ((session-id (plist-get session :id)))
      (if (orchid-session-running-p session-id)
          (progn
            (unless orchid-session-browser--marked-sessions
              (setq orchid-session-browser--marked-sessions (make-hash-table :test 'equal)))
            (puthash session-id 'kill orchid-session-browser--marked-sessions)
            (cl-incf orchid-session-browser--selected)
            (orchid-session-browser--populate))
        (message "Session has no running process to kill")))))

(defun orchid-session-browser-unmark ()
  "Remove mark from selected session."
  (interactive)
  (when-let ((session (orchid-session-browser--selected-session)))
    (when orchid-session-browser--marked-sessions
      (remhash (plist-get session :id) orchid-session-browser--marked-sessions)
      (orchid-session-browser--populate))))

(defun orchid-session-browser-execute ()
  "Execute all marked operations (delete sessions, stop processes)."
  (interactive)
  (when (and orchid-session-browser--marked-sessions
             (> (hash-table-count orchid-session-browser--marked-sessions) 0))
    (let ((count (hash-table-count orchid-session-browser--marked-sessions)))
      (when (yes-or-no-p (format "Execute %d marked operation(s)? " count))
        (let ((deleted-count 0)
              (killed-count 0)
              (failed 0)
              (succeeded-ids nil))
          (maphash
           (lambda (session-id mark-type)
             (cond
              ((eq mark-type 'delete)
               (let ((result (orchid-core-delete session-id)))
                 (if (plist-get result :success)
                     (progn
                       (setq deleted-count (1+ deleted-count))
                       (push session-id succeeded-ids))
                   (setq failed (1+ failed)))))
              ((eq mark-type 'kill)
               (let ((result (orchid-core-stop session-id)))
                 (if (plist-get result :success)
                     (progn
                       (setq killed-count (1+ killed-count))
                       (push session-id succeeded-ids))
                   (setq failed (1+ failed)))))))
           orchid-session-browser--marked-sessions)
          (dolist (session-id succeeded-ids)
            (remhash session-id orchid-session-browser--marked-sessions))
          (orchid-session-browser-refresh)
          (let ((msg-parts nil))
            (when (> deleted-count 0)
              (push (format "Deleted %d session%s" deleted-count (if (= deleted-count 1) "" "s"))
                    msg-parts))
            (when (> killed-count 0)
              (push (format "Killed %d process%s" killed-count (if (= killed-count 1) "" "es"))
                    msg-parts))
            (when (> failed 0)
              (push (format "%d failed" failed) msg-parts))
            (message "%s" (string-join (reverse msg-parts) ", "))))))))

(provide 'browser/orchid-browser-marks)

;;; orchid-browser-marks.el ends here
