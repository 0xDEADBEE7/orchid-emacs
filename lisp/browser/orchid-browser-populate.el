;;; orchid-browser-populate.el --- Populate logic for Orchid session browser -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Session data helpers and seek-based render logic for the Orchid session browser.

;;; Code:

(require 'seek)
(require 'session/orchid-session)
(require 'browser/orchid-browser-format)
(require 'browser/orchid-browser-search)

(defvar-local orchid-session-browser--search-query "")
(defvar-local orchid-session-browser--selected 0)
(defvar-local orchid-session-browser--scroll-offset 0)
(defvar-local orchid-session-browser--mode 'normal)
(defvar-local orchid-session-browser--marked-sessions nil)

;;; Row cache
;;
;; Sorted rows and rendered strings are cached to avoid redundant work on
;; every keypress.  The sorted-rows cache invalidates when the registry
;; identity changes (different set of IDs or updated_at values).
;; The row-strings cache invalidates per-session when :running or mark changes.

(defvar-local orchid-session-browser--sorted-rows nil
  "Cached sorted session list.")
(defvar-local orchid-session-browser--sorted-rows-key nil
  "Fingerprint of the registry state that produced the sorted-rows cache.")
(defvar-local orchid-session-browser--row-strings nil
  "Hash table: session-id -> rendered row string.")

(defun orchid-session-browser--registry-key (sessions)
  "Return a cheap fingerprint of SESSIONS for cache invalidation."
  (mapconcat (lambda (s)
               (concat (or (plist-get s :id) "")
                       (or (plist-get s :updated_at) "")))
             sessions ""))

(defun orchid-session-browser--sorted-rows ()
  "Return sorted sessions, using cache when the registry hasn't changed."
  (let* ((sessions (orchid-session-list))
         (key (orchid-session-browser--registry-key sessions)))
    (unless (equal key orchid-session-browser--sorted-rows-key)
      (setq orchid-session-browser--sorted-rows
            (orchid-session-browser--sort-sessions sessions)
            orchid-session-browser--sorted-rows-key key
            orchid-session-browser--row-strings nil))
    orchid-session-browser--sorted-rows))

(defun orchid-session-browser--invalidate-row (session-id)
  "Drop the cached rendered string for SESSION-ID."
  (when orchid-session-browser--row-strings
    (remhash session-id orchid-session-browser--row-strings)))

(defun orchid-session-browser--fetch-policies (&optional callback)
  "Return policy resource names, optionally asynchronously."
  (let ((result (orchid-core-list-policies callback)))
    (when (and result (plist-get result :success))
      (plist-get result :data))))

(defun orchid-session-browser--fetch-prompts (&optional callback)
  "Return prompt resource names, optionally asynchronously."
  (let ((result (orchid-core-list-prompts callback)))
    (when (and result (plist-get result :success))
      (plist-get result :data))))

(defun orchid-session-browser--sort-sessions (sessions)
  "Sort SESSIONS by updated_at date, most recent first."
  (sort (copy-sequence sessions)
        (lambda (a b)
          (let ((time-a (plist-get a :updated_at))
                (time-b (plist-get b :updated_at)))
            (cond
             ((and time-a time-b) (string> time-a time-b))
             (time-a t)
             (time-b nil)
             (t nil))))))

(defun orchid-session-browser--get-session-status (session)
  "Return plist with :buffer status and :process-running for SESSION."
  (let* ((has-chat (buffer-live-p (plist-get session :chat-buffer)))
         (has-log  (buffer-live-p (plist-get session :log-buffer)))
         (process-running (plist-get session :running))
         (base-status (if (or has-chat has-log) 'active 'idle)))
    (list :buffer base-status :process-running process-running)))

(defun orchid-session-browser--filter (query session)
  "Return non-nil if SESSION matches QUERY."
  (orchid-browser--fuzzy-match
   query
   (concat (orchid-browser-format-label session)
           (orchid-browser-format-status
            (orchid-session-browser--get-session-status session))
           (or (plist-get session :updated_at) ""))))

(defun orchid-session-browser--render-row (session _width _selected-p)
  "Return cached rendered row string for SESSION, computing if stale."
  (let* ((session-id (plist-get session :id))
         (running    (plist-get session :running))
         (mark       (and orchid-session-browser--marked-sessions
                          (gethash session-id orchid-session-browser--marked-sessions)))
         (cache-key  (list running mark))
         (cache      (or orchid-session-browser--row-strings
                         (setq orchid-session-browser--row-strings
                               (make-hash-table :test 'equal))))
         (entry      (gethash session-id cache)))
    (if (and entry (equal (car entry) cache-key))
        (cdr entry)
      (let ((str (orchid-browser-format-entry-line
                  session
                  orchid-session-browser--marked-sessions
                  'orchid-session-browser-active
                  'orchid-session-browser-idle)))
        (puthash session-id (cons cache-key str) cache)
        str))))

(defun orchid-session-browser--make-browser ()
  "Build a seek-browser struct from current buffer-local state."
  (make-seek-browser
   :all-rows      (orchid-session-browser--sorted-rows)
   :selected      orchid-session-browser--selected
   :scroll-offset orchid-session-browser--scroll-offset
   :title         " Orchid Sessions "
   :columns       (format "%-30s  %-10s %s" "LABEL" "STATUS" "UPDATED")
   :search        orchid-session-browser--search-query
   :search-mode   orchid-session-browser--mode
   :filter-fn     #'orchid-session-browser--filter
   :render-row    #'orchid-session-browser--render-row))

(defun orchid-session-browser--populate ()
  "Clamp selection and re-render the browser via seek."
  (let ((b (orchid-session-browser--make-browser)))
    (pcase-let ((`(,sel . ,off) (seek-clamp b)))
      (setq orchid-session-browser--selected sel
            orchid-session-browser--scroll-offset off)
      (setf (seek-browser-selected b) sel
            (seek-browser-scroll-offset b) off))
    (seek-render b)))

(defun orchid-session-browser--selected-session ()
  "Return the session at the current selected index, or nil."
  (nth orchid-session-browser--selected
       (seek-filtered-rows (orchid-session-browser--make-browser))))

(provide 'browser/orchid-browser-populate)

;;; orchid-browser-populate.el ends here
