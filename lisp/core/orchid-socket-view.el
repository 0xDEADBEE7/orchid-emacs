;;; orchid-socket-view.el --- Live shell view for Orchid chat -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Inserts a collapsible shell-output region directly below the chat separator.
;;
;; Collapsed (just the bar, TAB to expand):
;;
;;   ████████████████████████████████████████████████████████████████████████████████
;;
;; Expanded (cmd + last N output lines, TAB to collapse):
;;
;;   ┌shell─────────────────────────────────────────────────────────────────────────┐
;;   │ $ ./script.sh                                                                │
;;   │   line 1                                                                     │
;;   │   line 2                                                                     │
;;   └──────────────────────────────────────────────────────────────────────────────┘
;;   ████████████████████████████████████████████████████████████████████████████████
;;
;; Content is truncated at the box width — no line wrapping.  Multi-line cmds are
;; truncated at the first newline.
;;
;; The entire region (body + bar) is owned by this module.  It is inserted at
;; INSERT-POS and removed cleanly by `orchid-socket-view-stop'.
;;
;; Public API:
;;   orchid-socket-view-start SESSION-ID INSERT-POS
;;   orchid-socket-view-reconnect SESSION-ID
;;   orchid-socket-view-disconnect
;;   orchid-socket-view-stop
;;   orchid-socket-view-clear
;;   orchid-socket-view-toggle-at-point

;;; Code:

(require 'core/orchid-faces)
(require 'log/orchid-logging)
(require 'json)

;;; Customisation

(defcustom orchid-socket-view-lines 5
  "Number of output rows shown when expanded."
  :type 'integer
  :group 'orchid-chat)

(defcustom orchid-socket-view-retry-interval 1
  "Seconds between socket connection retries."
  :type 'number
  :group 'orchid-chat)

(defcustom orchid-socket-view-max-retries 20
  "Maximum connection attempts before giving up."
  :type 'integer
  :group 'orchid-chat)

;;; Buffer-local state

(defvar-local orchid-socket-view--process nil)
(defvar-local orchid-socket-view--region-start nil "Marker at start of owned region.")
(defvar-local orchid-socket-view--region-end   nil "Marker after end of owned region.")
(defvar-local orchid-socket-view--section-id   nil "Invisibility spec symbol for the body.")
(defvar-local orchid-socket-view--collapsed    t)
(defvar-local orchid-socket-view--cmd          nil "Pinned command line.")
(defvar-local orchid-socket-view--lines        nil "Output ring, newest first.")
(defvar-local orchid-socket-view--partial      "" "Incomplete line buffer.")
(defvar-local orchid-socket-view--prev-cr      nil "Non-nil if last dispatched line ended with \\r.")
(defvar-local orchid-socket-view--session-id   nil)

;;; Constants

(defconst orchid-socket-view--width 80
  "Total column width of the shell box, matching the progress bar.")

(defconst orchid-socket-view--bar
  (propertize (concat (make-string 80 ?\u2588) "\n")
              'face 'orchid-socket-view-header-face
              'read-only t
              'rear-nonsticky t
              'orchid-socket-view-bar t)
  "Immutable bar string — properties are set at load time.")

;;; Helpers

(defun orchid-socket-view--active-p ()
  (and orchid-socket-view--region-start
       (marker-buffer orchid-socket-view--region-start)))

(defun orchid-socket-view--sock-path (session-id)
  (expand-file-name
   (format "~/.config/orchid/conversations/%s/stream.sock" session-id)))

;;; Box rendering helpers

(defun orchid-socket-view--truncate (str max-width)
  "Return STR truncated to MAX-WIDTH display columns, stopping at the first newline.
Uses `string-width' to account for tabs and wide characters."
  (let* ((nl  (string-match-p "\n" str))
         (s   (if nl (substring str 0 nl) str)))
    ;; Walk chars until display width would exceed max-width.
    (let ((w 0) (i 0) (len (length s)))
      (while (and (< i len) (<= (+ w (char-width (aref s i))) max-width))
        (setq w (+ w (char-width (aref s i)))
              i (1+ i)))
      (substring s 0 i))))

(defun orchid-socket-view--box-top ()
  "Return the top border: ┌shell──────┐\\n (total width = orchid-socket-view--width)."
  (let* ((label  "shell")
         (dashes (- orchid-socket-view--width 2 (length label)))
         (line   (concat "┌" label (make-string dashes ?─) "┐\n")))
    (propertize line 'face 'orchid-socket-view-border-face 'read-only t 'rear-nonsticky t)))

(defun orchid-socket-view--box-bottom ()
  "Return the bottom border: └──────────┘\\n."
  (let* ((dashes (- orchid-socket-view--width 2))
         (line   (concat "└" (make-string dashes ?─) "┘\n")))
    (propertize line 'face 'orchid-socket-view-border-face 'read-only t 'rear-nonsticky t)))

(defun orchid-socket-view--box-row (prefix text face)
  "Return one box row: │<PREFIX><TEXT><pad> │\\n, total width = orchid-socket-view--width.
PREFIX is a literal string (e.g. \"$ \" or \"  \").  FACE applies to the content.
Border glyphs always use orchid-socket-view-border-face."
  ;; layout: │ + space + prefix + text + pad + space + │
  (let* ((available (- orchid-socket-view--width 4 (string-width prefix)))
         (txt       (orchid-socket-view--truncate text available))
         (pad       (make-string (max 0 (- available (string-width txt))) ?\s))
         (border    (propertize "│" 'face 'orchid-socket-view-border-face))
         (content   (propertize (concat " " prefix txt pad " ")
                                'face face)))
    (propertize (concat border content border "\n")
                'read-only t 'rear-nonsticky t)))

;;; Region management

(defun orchid-socket-view--insert (insert-pos)
  "Insert the shell-view region at INSERT-POS.
Layout: [body (hidden when collapsed)] [bar]
Both are inside the owned region so stop can delete them atomically."
  (save-excursion
    (let* ((inhibit-read-only t)
           (id (intern (format "orchid-sv-%d" (round (* 1000 (float-time)))))))
      (setq orchid-socket-view--section-id id)
      (unless (listp buffer-invisibility-spec)
        (setq buffer-invisibility-spec nil))
      (add-to-invisibility-spec id)
      (goto-char insert-pos)
      (setq orchid-socket-view--region-start (copy-marker (point) nil))
      ;; Bar is always visible; body is inserted before it.
      (insert orchid-socket-view--bar)
      (setq orchid-socket-view--region-end (copy-marker (point) t)))))

(defun orchid-socket-view--redraw ()
  "Replace body content between region-start and the bar.
Body = box (top + cmd + N output rows + bottom), always rendered at fixed height.
Invisible when collapsed. Preserves point if it was inside the body."
  (when (orchid-socket-view--active-p)
    (let* ((inhibit-read-only t)
           (id      orchid-socket-view--section-id)
           (hidden  orchid-socket-view--collapsed)
           (rstart  (marker-position orchid-socket-view--region-start))
           (bar-pos (- (marker-position orchid-socket-view--region-end)
                       (length orchid-socket-view--bar)))
           (pt-offset (when (and (>= (point) rstart) (< (point) bar-pos))
                        (- (point) rstart))))
      (save-excursion
        (delete-region rstart bar-pos)
        (goto-char rstart)
        (let* ((beg   (point))
               (lines orchid-socket-view--lines)
               (pad-n (max 0 (- orchid-socket-view-lines (length lines)))))
          (insert (orchid-socket-view--box-top))
          ;; cmd row — blank when no cmd is set
          (insert (orchid-socket-view--box-row "$ " (or orchid-socket-view--cmd "")
                                               'orchid-socket-view-border-face))
          ;; output rows — real content newest-last, then blank padding
          (dolist (line (reverse lines))
            (insert (orchid-socket-view--box-row "  " line 'shadow)))
          (dotimes (_ pad-n)
            (insert (orchid-socket-view--box-row "  " "" 'shadow)))
          (insert (orchid-socket-view--box-bottom))
          (put-text-property beg (point) 'invisible (and hidden id))))
      (when pt-offset
        (let ((new-end (- (marker-position orchid-socket-view--region-end)
                          (length orchid-socket-view--bar))))
          (goto-char (min (+ rstart pt-offset) (max rstart (1- new-end)))))))))

;;; Input processing

(defun orchid-socket-view--extract-cmd (json-line)
  "Return :cmd from a tool_start JSON-LINE, or nil."
  (condition-case nil
      (let* ((obj  (json-parse-string json-line :object-type 'plist))
             (type (plist-get obj :type))
             (cmd  (plist-get obj :cmd)))
        (when (and (equal type "tool_start") cmd) cmd))
    (error nil)))

(defun orchid-socket-view--push (line replace)
  "Add LINE to the output ring.  When REPLACE, overwrite the top entry."
  ;; Cross-chunk replace: if the previous chunk ended on a \r, this first line
  ;; of the new chunk is still a spinner update and should replace the top entry.
  (let ((do-replace (or replace orchid-socket-view--prev-cr)))
    (if (and do-replace orchid-socket-view--lines)
        (setcar orchid-socket-view--lines line)
      (push line orchid-socket-view--lines)))
  (when (> (length orchid-socket-view--lines) orchid-socket-view-lines)
    (setq orchid-socket-view--lines
          (seq-take orchid-socket-view--lines orchid-socket-view-lines)))
  (orchid-socket-view--redraw)
  (when (get-buffer-window (current-buffer)) (redisplay t)))

(defun orchid-socket-view--handle-line (line replace)
  "Dispatch a complete LINE from the stream."
  (unless (string-empty-p line)
    (cond
     ((string-prefix-p "{\"" line)
      (when-let ((cmd (orchid-socket-view--extract-cmd line)))
        (orchid-socket-view-clear)
        (setq orchid-socket-view--cmd cmd)
        (orchid-socket-view--redraw)
        (when (get-buffer-window (current-buffer)) (redisplay t))))
     ((string-prefix-p "$ " line)
      (orchid-socket-view-clear)
      (setq orchid-socket-view--cmd (substring line 2))
      (orchid-socket-view--redraw)
      (when (get-buffer-window (current-buffer)) (redisplay t)))
     (t
      (orchid-socket-view--push line replace)))))

(defun orchid-socket-view--on-filter (proc chunk)
  "Process filter: parse CHUNK respecting \\r in-place replace semantics."
  (let ((buf (process-buffer proc)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (let* ((data  (concat orchid-socket-view--partial chunk))
               (len   (length data))
               (i     0) (line-start 0) (replace nil))
          (while (< i len)
            (let ((ch (aref data i)))
              (cond
               ;; \r\n — \r is the signal, next line replaces this one
               ((and (eq ch ?\r) (< (1+ i) len) (eq (aref data (1+ i)) ?\n))
                (orchid-socket-view--handle-line (substring data line-start i) replace)
                (setq orchid-socket-view--prev-cr t
                      replace t  line-start (+ i 2)  i (+ i 2)))
               ;; bare \r — same signal
               ((eq ch ?\r)
                (orchid-socket-view--handle-line (substring data line-start i) replace)
                (setq orchid-socket-view--prev-cr t
                      replace t  line-start (1+ i)  i (1+ i)))
               ;; \n — plain new line, clear replace state
               ((eq ch ?\n)
                (orchid-socket-view--handle-line (substring data line-start i) replace)
                (setq orchid-socket-view--prev-cr nil
                      replace nil  line-start (1+ i)  i (1+ i)))
               (t (setq i (1+ i))))))
          (setq orchid-socket-view--partial
                (if (< line-start len) (substring data line-start) "")))))))

(defun orchid-socket-view--on-sentinel (_proc event)
  (orchid-log "[socket-view] sentinel: %s" (string-trim event)))

(defun orchid-socket-view--connect (buf session-id attempt)
  "Connect to SESSION-ID stream.sock in BUF, retrying if not yet present."
  (let ((path (orchid-socket-view--sock-path session-id)))
    (cond
     ((not (buffer-live-p buf)) nil)
     ((file-exists-p path)
      (with-current-buffer buf
        (condition-case err
            (setq orchid-socket-view--process
                  (make-network-process
                   :name     (format "orchid-sv-%s" session-id)
                   :buffer   buf
                   :family   'local
                   :service  path
                   :filter   #'orchid-socket-view--on-filter
                   :sentinel #'orchid-socket-view--on-sentinel
                   :noquery  t))
          (error (orchid-log "[socket-view] connect error: %s"
                             (error-message-string err))))))
     ((< attempt orchid-socket-view-max-retries)
      (run-with-timer orchid-socket-view-retry-interval nil
                      (lambda ()
                        (orchid-socket-view--connect buf session-id (1+ attempt)))))
     (t (orchid-log "[socket-view] gave up after %d attempts" attempt)))))

;;; Public API

(defun orchid-socket-view-start (session-id insert-pos)
  "Insert shell-view region at INSERT-POS and connect to SESSION-ID socket."
  (setq orchid-socket-view--session-id session-id
        orchid-socket-view--lines      nil
        orchid-socket-view--partial    ""
        orchid-socket-view--cmd        nil
        orchid-socket-view--collapsed  t)
  (orchid-socket-view--insert insert-pos)
  (orchid-socket-view--connect (current-buffer) session-id 0))

(defun orchid-socket-view-clear ()
  "Reset output data (cmd and lines) without touching collapsed state."
  (setq orchid-socket-view--lines    nil
        orchid-socket-view--partial  ""
        orchid-socket-view--cmd      nil
        orchid-socket-view--prev-cr  nil)
  (orchid-socket-view--redraw))

(defun orchid-socket-view--point-in-region-p ()
  "Non-nil if point is anywhere within the shell-view region."
  (and (orchid-socket-view--active-p)
       (>= (point) (marker-position orchid-socket-view--region-start))
       (<  (point) (marker-position orchid-socket-view--region-end))))

(defun orchid-socket-view-toggle-at-point ()
  "Toggle expand/collapse if point is on the bar or inside the region.
Returns t if toggled."
  (interactive)
  (when (orchid-socket-view--point-in-region-p)
    (setq orchid-socket-view--collapsed (not orchid-socket-view--collapsed))
    (orchid-socket-view--redraw)
    t))

(defun orchid-socket-view-region-end ()
  "Return the buffer position after the bar (where user input begins).
Returns nil if the region is not active."
  (when (orchid-socket-view--active-p)
    (marker-position orchid-socket-view--region-end)))

(defun orchid-socket-view-disconnect ()
  "Close the socket connection but leave the region and its content intact."
  (when orchid-socket-view--process
    (condition-case nil (delete-process orchid-socket-view--process) (error nil))
    (setq orchid-socket-view--process nil)))

(defun orchid-socket-view-reconnect (session-id)
  "Reconnect the existing region to SESSION-ID's socket.
Use this when the real session-id becomes known after the region was inserted
with a placeholder id (e.g. \"pending\")."
  (orchid-socket-view-disconnect)
  (setq orchid-socket-view--session-id session-id)
  (orchid-socket-view--connect (current-buffer) session-id 0))

(defun orchid-socket-view-stop ()
  "Disconnect and delete the entire region."
  (when orchid-socket-view--process
    (condition-case nil (delete-process orchid-socket-view--process) (error nil))
    (setq orchid-socket-view--process nil))
  (when (orchid-socket-view--active-p)
    (let ((inhibit-read-only t))
      (delete-region orchid-socket-view--region-start
                     orchid-socket-view--region-end))
    (set-marker orchid-socket-view--region-start nil)
    (set-marker orchid-socket-view--region-end   nil)
    (setq orchid-socket-view--region-start nil
          orchid-socket-view--region-end   nil))
  (setq orchid-socket-view--lines      nil
        orchid-socket-view--partial    ""
        orchid-socket-view--cmd        nil
        orchid-socket-view--collapsed  t
        orchid-socket-view--prev-cr    nil
        orchid-socket-view--session-id nil
        orchid-socket-view--section-id nil))

(provide 'core/orchid-socket-view)

;;; orchid-socket-view.el ends here
