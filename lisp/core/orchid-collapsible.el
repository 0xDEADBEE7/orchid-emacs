;;; orchid-collapsible.el --- Collapsible text sections for Orchid -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Provides collapsible text sections using text properties.
;; Sections can be toggled between collapsed (showing only a stub) and
;; expanded (showing full details) by pressing TAB.
;;
;; Faces:
;; - `orchid-collapsible-stub-face': Face for collapsed section stubs
;; - `orchid-collapsible-detail-face': Face for expanded section details
;;
;; Both faces inherit from standard Emacs faces and will adapt to your theme.

;;; Code:

(require 'core/orchid-collapsible-toggle)

;;; Faces

(defface orchid-collapsible-stub-face
  '((t :inherit shadow))
  "Face for collapsed section stubs.
Uses shadow face to match processing indicator."
  :group 'orchid)

(defface orchid-collapsible-user-stub-face
  '((t :inherit default))
  "Face for user message stubs.
Uses default face to keep white color."
  :group 'orchid)

(defface orchid-collapsible-detail-face
  '((t :inherit default))
  "Face for expanded section details."
  :group 'orchid)

;;; Private Variables

(defvar orchid-collapsible--counter 0
  "Counter for generating unique collapsible section IDs.
Not buffer-local to ensure unique IDs across all buffers.")

(defvar orchid-collapsible--lazy-stats
  '(:total-lazy 0
    :total-materialized 0
    :total-format-time 0.0)
  "Statistics for lazy formatting performance.")

;;; Public API

(defun orchid-collapsible-create (stub-text detail-text &optional initially-collapsed stub-face)
  "Create a collapsible section with STUB-TEXT and DETAIL-TEXT.
If INITIALLY-COLLAPSED is non-nil, the section starts collapsed.
STUB-FACE specifies the face for the stub (defaults to
\`orchid-collapsible-stub-face').
Returns the formatted string with text properties."
  ;; Generate unique ID for this section (thread-safe counter)
  (setq orchid-collapsible--counter (1+ orchid-collapsible--counter))
  (let* ((section-id (intern (format "orchid-collapsible-%d" orchid-collapsible--counter)))
         (collapsed initially-collapsed)
         (face (or stub-face 'orchid-collapsible-stub-face)))

    (concat
     ;; Stub (always visible, clickable)
     (propertize stub-text
                 'orchid-collapsible t
                 'orchid-collapsible-id section-id
                 'orchid-collapsible-region 'stub
                 'orchid-collapsible-state (if collapsed 'collapsed 'expanded)
                 'face face
                 'help-echo "Press TAB to toggle")
     ;; Detail (collapsible) - includes leading newline so it disappears when collapsed
     ;; Use add-text-properties to preserve existing face properties
     (let ((detail (concat "\n" detail-text)))
       (add-text-properties 0 (length detail)
                           (list 'orchid-collapsible t
                                 'orchid-collapsible-id section-id
                                 'orchid-collapsible-region 'detail
                                 'invisible (if collapsed t nil)
                                 'help-echo "Press TAB to collapse")
                           detail)
       detail))))

(defun orchid-collapsible-create-lazy (stub-text detail-fn &optional initially-collapsed stub-face)
  "Create a collapsible section with LAZY detail formatting.

STUB-TEXT: Text shown when collapsed (always visible)
DETAIL-FN: Zero-argument function that returns formatted detail text.
           Called only on first expand.  Should be fast (<5ms).
INITIALLY-COLLAPSED: If non-nil, start collapsed (default nil)
STUB-FACE: Face for stub text (default `orchid-collapsible-stub-face')

Returns a propertized string ready to insert into buffer.

Example:
  (orchid-collapsible-create-lazy
   \"[Assistant: Hello world]\"
   (lambda () (concat (propertize \"Assistant: \" \\='face \\='bold) \"Hello world\"))
   t)"
  ;; Update stats
  (plist-put orchid-collapsible--lazy-stats :total-lazy
            (1+ (plist-get orchid-collapsible--lazy-stats :total-lazy)))

  ;; Generate unique ID
  (setq orchid-collapsible--counter (1+ orchid-collapsible--counter))
  (let* ((section-id (intern (format "orchid-collapsible-%d" orchid-collapsible--counter)))
         (collapsed (if initially-collapsed t nil))
         (face (or stub-face 'orchid-collapsible-stub-face)))

    (concat
     ;; Stub (always visible, clickable)
     (propertize stub-text
                 'orchid-collapsible t
                 'orchid-collapsible-id section-id
                 'orchid-collapsible-region 'stub
                 'orchid-collapsible-state (if collapsed 'collapsed 'expanded)
                 'orchid-collapsible-lazy t              ; Mark as lazy
                 'orchid-collapsible-detail-fn detail-fn ; Store formatter
                 'face face
                 'help-echo "Press TAB to expand")

     ;; Detail placeholder (empty, replaced on first expand)
     (propertize "\n"
                 'orchid-collapsible t
                 'orchid-collapsible-id section-id
                 'orchid-collapsible-region 'detail
                 'invisible (if collapsed t nil)
                 'help-echo "Press TAB to collapse"))))

(defun orchid-collapsible-toggle-at-point ()
  "Toggle the collapsible section at point.
Returns t if a section was toggled, nil otherwise."
  (interactive)
  (let* ((section-id (get-text-property (point) 'orchid-collapsible-id))
         (is-collapsible (get-text-property (point) 'orchid-collapsible)))
    (if (and is-collapsible section-id)
        (progn
          (orchid-collapsible--toggle-section section-id)
          t)
      nil)))

;;; Private Functions

(defun orchid-collapsible--toggle-section (section-id)
  "Toggle visibility of section with SECTION-ID.
Materializes lazy detail on first expand."
  (save-excursion
    (let ((buffer-read-only nil)
          (inhibit-read-only t))

      (orchid-collapsible--log "\n=== toggle-section %S ===" section-id)

      ;; Phase 1: find stub, compute new state
      (pcase (orchid-collapsible--read-stub-state section-id)
        (`(,new-state ,detail-fn ,stub-pos)

         (orchid-collapsible--log "  stub found at %d, new-state=%S, has-detail-fn=%S"
           stub-pos new-state (not (null detail-fn)))

         ;; Phase 2: materialize lazy detail if needed (before toggling visibility)
         (when detail-fn
           (orchid-collapsible--materialize-detail section-id detail-fn stub-pos))

         ;; Phase 3: toggle visibility
         (orchid-collapsible--log "  applying visibility: %S -> %S" section-id new-state)
         (orchid-collapsible--apply-visibility section-id new-state)
         (orchid-collapsible--log "  done"))

        (_ (orchid-collapsible--log "  no stub found for %S" section-id))))))

(defun orchid-collapsible-report-stats ()
  "Report lazy formatting statistics."
  (interactive)
  (let ((total-lazy (plist-get orchid-collapsible--lazy-stats :total-lazy))
        (total-mat (plist-get orchid-collapsible--lazy-stats :total-materialized))
        (total-time (plist-get orchid-collapsible--lazy-stats :total-format-time)))
    (message "Lazy Formatting Stats:\n  Created: %d\n  Materialized: %d (%.1f%%)\n  Total time: %.3fs\n  Avg time: %.3fs"
            total-lazy
            total-mat
            (if (> total-lazy 0)
                (* 100.0 (/ (float total-mat) (float total-lazy)))
              0.0)
            total-time
            (if (> total-mat 0)
                (/ total-time (float total-mat))
              0.0))))


(provide 'core/orchid-collapsible)

;;; orchid-collapsible.el ends here
