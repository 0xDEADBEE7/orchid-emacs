;;; orchid-collapsible-toggle.el --- Toggle traversal helpers for collapsible sections -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Private traversal helpers for orchid-collapsible.el, extracted to keep
;; that module within the 200-line target.  Not intended for direct use.

;;; Code:

;; Performance stats plist defined in orchid-collapsible.el
(defvar orchid-collapsible--lazy-stats)

(defvar orchid-collapsible-debug nil
  "When non-nil, log collapsible toggle internals to *orchid-collapsible-debug*.")

(defun orchid-collapsible--log (fmt &rest args)
  "Log FMT+ARGS to *orchid-collapsible-debug* when `orchid-collapsible-debug' is set."
  (when orchid-collapsible-debug
    (with-current-buffer (get-buffer-create "*orchid-collapsible-debug*")
      (goto-char (point-max))
      (insert (apply #'format fmt args) "\n"))))

(defun orchid-collapsible--materialize-detail (section-id detail-fn stub-pos)
  "Format and insert detail content for SECTION-ID using an overlay for visibility.
Calls DETAIL-FN, replaces the placeholder \\n with real content, creates an
overlay spanning the detail region to control visibility, and stores it on
the stub at STUB-POS so future toggles can find it."
  (let ((buffer-read-only nil)
        (inhibit-read-only t)
        (format-start (current-time))
        (end (point-max)))

    (orchid-collapsible--log "  materialize %S" section-id)

    (goto-char (point-min))
    (while (< (point) end)
      (when (and (eq (get-text-property (point) 'orchid-collapsible-id) section-id)
                 (eq (get-text-property (point) 'orchid-collapsible-region) 'detail))
        (let* ((detail-start (point))
               (detail-end (or (next-single-property-change (point) 'orchid-collapsible-region nil end)
                               end))
               (formatted-text
                (condition-case err
                    (funcall detail-fn)
                  (error (format "[Error formatting content: %S]" err)))))

          (let ((elapsed (float-time (time-subtract (current-time) format-start))))
            (plist-put orchid-collapsible--lazy-stats :total-materialized
                      (1+ (plist-get orchid-collapsible--lazy-stats :total-materialized)))
            (plist-put orchid-collapsible--lazy-stats :total-format-time
                      (+ elapsed (plist-get orchid-collapsible--lazy-stats :total-format-time))))

          ;; Replace the placeholder \n with \n + content, preserving inner text props
          (delete-region detail-start detail-end)
          (goto-char detail-start)
          (let ((ov-start (point)))
            (insert "\n" formatted-text)
            (let* ((ov-end (point))
                   ;; Create overlay spanning the full detail region (including inner stubs)
                   (ov (make-overlay ov-start ov-end nil t nil)))
              (overlay-put ov 'orchid-collapsible-id section-id)
              (overlay-put ov 'orchid-collapsible-region 'detail)
              (overlay-put ov 'invisible nil)
              (orchid-collapsible--log "  created overlay %S [%d,%d)" section-id ov-start ov-end)
              ;; Store overlay on the stub so we can find it without scanning
              (when stub-pos
                (let ((stub-end (or (next-single-property-change stub-pos 'orchid-collapsible-region
                                                                  nil (point-max))
                                    (point-max))))
                  (put-text-property stub-pos stub-end 'orchid-collapsible-overlay ov)))))
          (goto-char (point-max))))

      (goto-char (or (next-single-property-change (point) 'orchid-collapsible-region nil end)
                    end)))

    ;; Remove lazy markers so we don't re-materialize
    (when stub-pos
      (let ((stub-end (or (next-single-property-change stub-pos 'orchid-collapsible-region nil (point-max))
                         (point-max))))
        (remove-text-properties stub-pos stub-end
                              '(orchid-collapsible-lazy nil
                                orchid-collapsible-detail-fn nil))))))

(defun orchid-collapsible--read-stub-state (section-id)
  "Find the stub for SECTION-ID and return a list (new-state detail-fn stub-pos).
Returns nil if no stub is found."
  (let ((result nil)
        (end (point-max)))
    (goto-char (point-min))
    (while (and (< (point) end) (not result))
      (when (and (eq (get-text-property (point) 'orchid-collapsible-id) section-id)
                 (eq (get-text-property (point) 'orchid-collapsible-region) 'stub))
        (let* ((stub-pos (point))
               (current-state (get-text-property (point) 'orchid-collapsible-state))
               (new-state (if (eq current-state 'collapsed) 'expanded 'collapsed))
               (detail-fn (when (and (eq new-state 'expanded)
                                     (get-text-property (point) 'orchid-collapsible-lazy))
                            (get-text-property (point) 'orchid-collapsible-detail-fn)))
               (stub-end (or (next-single-property-change (point) 'orchid-collapsible-region nil end)
                             end)))
          (orchid-collapsible--log "  read-stub %S: cur=%S new=%S lazy=%S"
            section-id current-state new-state (not (null detail-fn)))
          (put-text-property (point) stub-end 'orchid-collapsible-state new-state)
          (setq result (list new-state detail-fn stub-pos))))
      (goto-char (or (next-single-property-change (point) 'orchid-collapsible-region nil end)
                    end)))
    result))

(defun orchid-collapsible--apply-visibility (section-id new-state)
  "Set detail region of SECTION-ID visible or invisible based on NEW-STATE.
For lazy sections that have been materialized, uses the stored overlay.
For non-lazy sections, falls back to text property scanning."
  (let ((invisible-val (if (eq new-state 'collapsed) t nil))
        (end (point-max)))

    (orchid-collapsible--log "  apply-vis %S -> %S" section-id new-state)

    ;; Try overlay approach first: find stub and check for stored overlay
    (let ((ov (orchid-collapsible--find-detail-overlay section-id)))
      (if ov
          (progn
            (orchid-collapsible--log "  using overlay [%d,%d)"
              (overlay-start ov) (overlay-end ov))
            (overlay-put ov 'invisible invisible-val))

        ;; Fallback: text property scan for non-lazy (non-nested) sections
        (orchid-collapsible--log "  no overlay found, using text property scan")
        (goto-char (point-min))
        (while (< (point) end)
          (when (and (eq (get-text-property (point) 'orchid-collapsible-id) section-id)
                     (eq (get-text-property (point) 'orchid-collapsible-region) 'detail))
            (let ((detail-end (or (next-single-property-change (point) 'orchid-collapsible-region nil end)
                                  end)))
              (orchid-collapsible--log "  text-prop detail span [%d,%d)" (point) detail-end)
              (put-text-property (point) detail-end 'invisible
                                 (if (eq new-state 'collapsed) t nil))
              (goto-char detail-end)))
          (goto-char (or (next-single-property-change (point) 'orchid-collapsible-region nil end)
                        end)))))))

(defun orchid-collapsible--find-detail-overlay (section-id)
  "Find the detail overlay stored on the stub for SECTION-ID, or nil."
  (let ((result nil)
        (end (point-max)))
    (goto-char (point-min))
    (while (and (< (point) end) (not result))
      (when (and (eq (get-text-property (point) 'orchid-collapsible-id) section-id)
                 (eq (get-text-property (point) 'orchid-collapsible-region) 'stub))
        (setq result (get-text-property (point) 'orchid-collapsible-overlay)))
      (goto-char (or (next-single-property-change (point) 'orchid-collapsible-region nil end)
                    end)))
    result))

(provide 'core/orchid-collapsible-toggle)

;;; orchid-collapsible-toggle.el ends here
