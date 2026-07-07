;;; orchid-parser-utils.el --- Shared utilities for parsers -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Shared utility functions for event parsers.
;; Provides timestamp formatting and stub formatting with timestamps.

;;; Code:

(require 'json)
(require 'diff-mode)

(declare-function parse-iso8601-time-string "time-date" (date-string))

;;; Faces

(defface orchid-diff-removed-face
  '((t :inherit diff-removed))
  "Face for removed lines in diff display."
  :group 'orchid)

(defface orchid-diff-added-face
  '((t :inherit diff-added))
  "Face for added lines in diff display."
  :group 'orchid)

(defface orchid-diff-context-face
  '((t :inherit diff-context))
  "Face for context lines in diff display."
  :group 'orchid)

(defun orchid-parser--truncate-path-left (path max-len)
  "Truncate PATH to MAX-LEN chars, cutting from the left.
Prepends '…' when truncation occurs."
  (if (> (length path) max-len)
      (concat "…" (substring path (- (length path) (1- max-len))))
    path))

(defun orchid-parser--format-timestamp (iso-timestamp)
  "Format ISO-TIMESTAMP to YYYY-MM-DD HH:MM:SS.
Returns formatted string or nil if timestamp is invalid."
  (when iso-timestamp
    (condition-case nil
        (let* ((time (parse-iso8601-time-string iso-timestamp))
               (decoded (decode-time time)))
          (format "%04d-%02d-%02d %02d:%02d:%02d"
                  (nth 5 decoded)  ; year
                  (nth 4 decoded)  ; month
                  (nth 3 decoded)  ; day
                  (nth 2 decoded)  ; hour
                  (nth 1 decoded)  ; minute
                  (nth 0 decoded))) ; second
      (error nil))))

(defun orchid-parser--format-stub-with-timestamp (stub-text timestamp)
  ;; timestamp arg name kept for compatibility; caller passes (plist-get data :ts)
  "Format STUB-TEXT with TIMESTAMP aligned to positions 0-53 and 59-79.
First bracket contains stub text (max 53 chars).
Second bracket contains timestamp (positions 59-79)."
  (let* ((formatted-timestamp (orchid-parser--format-timestamp timestamp))
         ;; Ensure stub doesn't exceed position 53
         (truncated-stub (if (> (length stub-text) 53)
                             (concat (substring stub-text 0 50) "...]")
                           stub-text))
         ;; Calculate padding needed to reach position 59
         (stub-length (length truncated-stub))
         (padding-needed (max 0 (- 59 stub-length)))
         (padding (make-string padding-needed ?\s)))
    (if formatted-timestamp
        (format "%s%s[%s]" truncated-stub padding formatted-timestamp)
      truncated-stub)))

;;; Diff formatting

(defun orchid-parser--format-edit-diff (old-string new-string)
  "Format OLD-STRING and NEW-STRING as a colored unified diff.
Returns a formatted string with proper faces for removed/added/context lines."
  (if (or (not old-string) (not new-string))
      (concat (when old-string
                (concat "  Old string:\n"
                        (mapconcat (lambda (line) (concat "    " line))
                                  (split-string old-string "\n")
                                  "\n")))
              (when new-string
                (concat "\n  New string:\n"
                        (mapconcat (lambda (line) (concat "    " line))
                                  (split-string new-string "\n")
                                  "\n"))))
    (with-temp-buffer
      (let ((old-buf (generate-new-buffer " *orchid-diff-old*"))
            (new-buf (generate-new-buffer " *orchid-diff-new*"))
            (diff-output nil))
        (unwind-protect
            (progn
              (with-current-buffer old-buf
                (insert old-string))
              (with-current-buffer new-buf
                (insert new-string))
              (let ((old-file (make-temp-file "orchid-diff-old"))
                    (new-file (make-temp-file "orchid-diff-new")))
                (unwind-protect
                    (progn
                      (with-current-buffer old-buf
                        (write-region (point-min) (point-max) old-file nil 'silent))
                      (with-current-buffer new-buf
                        (write-region (point-min) (point-max) new-file nil 'silent))
                      (let ((diff-command (format "diff -u %s %s"
                                                 (shell-quote-argument old-file)
                                                 (shell-quote-argument new-file))))
                        (shell-command diff-command (current-buffer))
                        (setq diff-output (buffer-string))))
                  (delete-file old-file)
                  (delete-file new-file))))
          (kill-buffer old-buf)
          (kill-buffer new-buf))
        (if (string-empty-p diff-output)
            "  No changes"
          (let ((lines (split-string diff-output "\n"))
                (formatted-lines '()))
            (dolist (line lines)
              (cond
               ((string-match-p "^---" line) nil)
               ((string-match-p "^\\+\\+\\+" line) nil)
               ((string-match-p "^@@" line)
                (push (propertize (concat "    " line "\n") 'face 'orchid-diff-context-face)
                      formatted-lines))
               ((string-prefix-p "-" line)
                (push (propertize (concat "    " line "\n") 'face 'orchid-diff-removed-face)
                      formatted-lines))
               ((string-prefix-p "+" line)
                (push (propertize (concat "    " line "\n") 'face 'orchid-diff-added-face)
                      formatted-lines))
               ((not (string-empty-p line))
                (push (propertize (concat "    " line "\n") 'face 'orchid-diff-context-face)
                      formatted-lines))))
            (concat "  Diff:\n"
                    (apply #'concat (nreverse formatted-lines)))))))))

(provide 'parsers/orchid-parser-utils)

;;; orchid-parser-utils.el ends here
