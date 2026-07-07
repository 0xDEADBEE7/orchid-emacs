;;; orchid-processing-indicator.el --- Process-based processing indicator -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Processing indicator that polls session status to determine when processing
;; completes.  Shows elapsed time and automatically stops when orchid goes idle.

;;; Code:

(require 'session/orchid-session)
(require 'log/orchid-logging)
(require 'core/orchid-processing-watch)
(require 'core/orchid-core)
(require 'core/orchid-socket-view)

;;; Buffer-Local State

(defvar-local orchid-processing--start-time nil
  "Time when processing started.")

(defvar-local orchid-processing--timer nil
  "Timer for updating elapsed time display.")

(defvar-local orchid-processing--watch nil
  "File-notify watch descriptor for metadata.json.")

(defvar-local orchid-processing--marker nil
  "Marker pointing to start of processing indicator.")

(defvar-local orchid-processing--session-id nil
  "Session ID whose process we're monitoring.")

(defvar-local orchid-processing--status-message nil
  "Current status message to display in the indicator.")

(defvar-local orchid-processing--token-estimate nil
  "Current token estimate read from metadata.json, or nil if unavailable.")

(defvar-local orchid-processing--finished nil
  "Non-nil if processing has finished.")

(defvar-local orchid-processing--seen-running nil
  "Non-nil once we have observed status=running at least once.
Guards against false finish on the initial metadata write.")

(defvar-local orchid-processing--chunk-count nil
  "Latest chunk count read from stream.state, or nil if unavailable.")

(defvar-local orchid-processing--chunk-baseline nil
  "Chunk count at the start of the current run, for relative display.")

;;; Private Functions

(defun orchid-processing--elapsed-seconds ()
  "Return seconds elapsed since processing started."
  (if orchid-processing--start-time
      (floor (- (float-time) orchid-processing--start-time))
    0))

(defun orchid-processing--read-stream-state (session-id)
  "Read chunk count from stream.state for SESSION-ID.
File format: '<epoch> <count>' on a single line.
Returns the integer packet count, or nil on error."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents
         (expand-file-name
          (format "~/.config/orchid/conversations/%s/stream.state" session-id)))
        (goto-char (point-min))
        (when (re-search-forward "[[:space:]]+\\([0-9]+\\)" nil t)
          (string-to-number (match-string 1))))
    (error nil)))

(defun orchid-processing--read-metadata (session-id)
  "Read and parse metadata.json for SESSION-ID.
Returns a plist or nil on error."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents
         (expand-file-name
          (format "~/.config/orchid/conversations/%s/metadata.json" session-id)))
        (goto-char (point-min))
        (json-parse-buffer :object-type 'plist))
    (error nil)))

(defun orchid-processing--read-status (session-id)
  "Read current status string from metadata.json for SESSION-ID.
Returns \"running\", \"idle\", or nil on error."
  (plist-get (orchid-processing--read-metadata session-id) :status))

(defun orchid-processing--token-suffix ()
  "Return propertized token suffix string, or empty string if estimate is nil or zero."
  (if (and orchid-processing--token-estimate
           (> orchid-processing--token-estimate 0))
      (propertize (format "~%dk tokens" (/ orchid-processing--token-estimate 1000))
                  'face 'shadow)
    ""))

(defun orchid-processing--build-indicator-line (elapsed)
  "Build the indicator line string for ELAPSED seconds.
Left: status + chunk count.  Right: token estimate (or blank)."
  (let* ((token-text  (orchid-processing--token-suffix))
         (token-plain (substring-no-properties token-text))
         (time-label  (if orchid-processing--finished
                          (format "[Finished: %ds]" elapsed)
                        (format "[Processing: %ds]" elapsed)))
         (chunk-label (when (and orchid-processing--chunk-count
                                 (> orchid-processing--chunk-count 0))
                        (let ((relative (- orchid-processing--chunk-count
                                          (or orchid-processing--chunk-baseline 0))))
                          (format "[Chunks: %d]" (max 0 relative)))))
         (status-plain (concat time-label (or chunk-label "")))
         (status-text  (propertize status-plain 'face 'shadow))
         (padding (max 1 (- 80 (length status-plain) (length token-plain)))))
    (concat status-text (make-string padding ?\s) token-text)))

(defun orchid-processing--update-display ()
  "Update indicator elapsed time display without displacing user cursor."
  (when (and orchid-processing--marker
             (marker-buffer orchid-processing--marker))
    (let* ((inhibit-read-only t)
           (elapsed (orchid-processing--elapsed-seconds))
           (new-line (orchid-processing--build-indicator-line elapsed))
           (buf (marker-buffer orchid-processing--marker))
           ;; Save point in every window showing this buffer so the update
           ;; cannot displace the user's cursor.
           (window-points
            (mapcar (lambda (w) (cons w (window-point w)))
                    (get-buffer-window-list buf nil t))))
      (with-current-buffer buf
        (save-excursion
          (goto-char orchid-processing--marker)
          (delete-region (line-beginning-position) (line-end-position))
          (insert new-line)))
      ;; Restore each window's point after the buffer modification.
      (dolist (wp window-points)
        (set-window-point (car wp) (cdr wp))))))

(defun orchid-processing-capture-chunk-baseline (session-id)
  "Capture current chunk count as the baseline for the next run.
Call this just before starting a new run for SESSION-ID.
If stream.state does not exist yet, baseline is set to 0."
  (setq orchid-processing--chunk-baseline
        (or (orchid-processing--read-stream-state session-id) 0)))

(defun orchid-processing--refresh-chunk-count ()
  "Read stream.state and update the cached chunk count."
  (when-let ((count (orchid-processing--read-stream-state orchid-processing--session-id)))
    (setq orchid-processing--chunk-count count)))

(defun orchid-processing--check-status ()
  "Read metadata and finish indicator if session is no longer running.
Called on timer tick as a fallback for missed file-notify events."
  (when (and orchid-processing--marker
             (marker-buffer orchid-processing--marker)
             (not orchid-processing--finished))
    (orchid-processing--refresh-chunk-count)
    (let* ((metadata (orchid-processing--read-metadata orchid-processing--session-id))
           (status  (plist-get metadata :status))
           (running (equal status "running"))
           (tokens  (plist-get metadata :token_estimate)))
      (when (integerp tokens)
        (orchid-processing-update-token-estimate tokens))
      (when running
        (setq orchid-processing--seen-running t))
      (orchid-session-notify-status-change orchid-processing--session-id running)
      (when (and orchid-processing--seen-running (not running))
        (orchid-log "Process finished (poll) after %ds" (orchid-processing--elapsed-seconds))
        (setq orchid-processing--finished t)
        (setq orchid-processing--status-message nil)
        (orchid-processing--update-display)
        (orchid-processing-stop)))))

;;; Public API

(defun orchid-processing-show (session-id &optional start-time)
  "Show processing indicator and watch SESSION-ID metadata.json for completion.
Uses file-notify to react to status changes without polling.
Optional START-TIME is a `float-time' value; defaults to now."
  (unless orchid-processing--marker
    (require 'filenotify)
    (setq orchid-processing--start-time (or start-time (float-time)))
    (setq orchid-processing--session-id session-id)
    (setq orchid-processing--status-message nil)
    (setq orchid-processing--finished nil)
    (setq orchid-processing--seen-running nil)
    (setq orchid-processing--chunk-count nil)
    ;; Pre-load token estimate and chunk count so they show immediately.
    (let ((tokens (plist-get (orchid-processing--read-metadata session-id) :token_estimate)))
      (when (and (integerp tokens) (> tokens 0))
        (setq orchid-processing--token-estimate tokens)))
    (orchid-processing--refresh-chunk-count)
    (let ((inhibit-read-only t))
      (insert "\n")
      (setq orchid-processing--marker (point-marker))
      (insert (orchid-processing--build-indicator-line
               (orchid-processing--elapsed-seconds)))
      (insert "\n"))
    (when orchid-processing--timer
      (cancel-timer orchid-processing--timer))
    (setq orchid-processing--timer
          (run-with-timer 1 1
                          (lambda (buf)
                            (when (and (buffer-live-p buf)
                                       (get-buffer-window buf))
                              (with-current-buffer buf
                                (orchid-processing--update-display)
                                (orchid-processing--check-status))))
                          (current-buffer)))
    ;; Watch metadata.json for status changes.
    (when orchid-processing--watch
      (file-notify-rm-watch orchid-processing--watch)
      (setq orchid-processing--watch nil))
    (let* ((metadata-path (expand-file-name
                           (format "~/.config/orchid/conversations/%s/metadata.json"
                                   session-id)))
           (buf (current-buffer)))
      (orchid-processing--attach-metadata-watch metadata-path buf session-id 0))))
  ;; Socket view is started by the caller after the separator is in place.

(defun orchid-processing-finish ()
  "Mark processing as finished and stop the indicator.
Call this when the run has already completed (e.g. after --await returns)."
  (when (and orchid-processing--marker
             (not orchid-processing--finished))
    (setq orchid-processing--finished t)
    (setq orchid-processing--status-message nil)
    (orchid-processing--update-display)
    (orchid-processing-stop)))

(defun orchid-processing-stop ()
  "Stop updating the processing indicator, leaving final time as a record."
  (when orchid-processing--marker
    (when orchid-processing--timer
      (cancel-timer orchid-processing--timer)
      (setq orchid-processing--timer nil))
    (when orchid-processing--watch
      (file-notify-rm-watch orchid-processing--watch)
      (setq orchid-processing--watch nil))
    (set-marker orchid-processing--marker nil)
    (setq orchid-processing--marker nil)
    (setq orchid-processing--start-time nil)
    (setq orchid-processing--session-id nil)
    (setq orchid-processing--status-message nil)
    (setq orchid-processing--finished nil)
    (setq orchid-processing--seen-running nil)
    (setq orchid-processing--chunk-count nil)
    (setq orchid-processing--chunk-baseline nil)
    ;; Disconnect socket but keep the region — user may still expand/collapse it.
    (orchid-socket-view-disconnect)
    ;; Move all windows showing this buffer to point-max so the user's cursor
    ;; lands in the editable input area after the sv bar, not inside the
    ;; response content that was streamed in before the bar.
    (let ((buf (current-buffer)))
      (dolist (win (get-buffer-window-list buf nil t))
        (set-window-point win (point-max))))))

(defun orchid-processing-update-status (message)
  "Update the processing indicator status MESSAGE.
MESSAGE should be a short string describing current activity
\(e.g., \='Running Bash\\=').
Pass nil to clear the status message and show generic \='Processing\='."
  (setq orchid-processing--status-message message))

(defun orchid-processing-update-token-estimate (estimate)
  "Update token estimate displayed on the indicator line.
ESTIMATE should be an integer token count, or nil to clear."
  (setq orchid-processing--token-estimate estimate))

(defun orchid-processing-hide ()
  "Remove processing indicator completely (for cleanup)."
  (when (and orchid-processing--marker
             (marker-buffer orchid-processing--marker))
    (let ((inhibit-read-only t))
      (save-excursion
        (goto-char orchid-processing--marker)
        (let ((start (line-beginning-position))
              (end (line-end-position)))
          (when (and (> start (point-min))
                     (save-excursion
                       (goto-char start)
                       (forward-line -1)
                       (looking-at "^[[:space:]]*$")))
            (setq start (line-beginning-position 0)))
          (when (and (< end (point-max))
                     (save-excursion
                       (goto-char end)
                       (forward-line 1)
                       (looking-at "^[[:space:]]*$")))
            (forward-line 1)
            (setq end (line-end-position)))
          (delete-region start (min (1+ end) (point-max)))))))
  (orchid-processing-stop))

(defun orchid-processing-cleanup ()
  "Clean up timer and file-notify watch on buffer close."
  (when orchid-processing--timer
    (cancel-timer orchid-processing--timer)
    (setq orchid-processing--timer nil))
  (when orchid-processing--watch
    (file-notify-rm-watch orchid-processing--watch)
    (setq orchid-processing--watch nil))
  (orchid-socket-view-stop))

(provide 'core/orchid-processing-indicator)

;;; orchid-processing-indicator.el ends here
