;;; orchid-parser-utils.el --- Shared utilities for parsers -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Shared utility functions for event parsers.
;; Provides timestamp formatting and stub formatting with timestamps.

;;; Code:

(require 'time-date)
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
        (let* ((time (date-to-time iso-timestamp))
               (decoded (decode-time time)))
          (format "%04d-%02d-%02d %02d:%02d:%02d"
                  (nth 5 decoded)  ; year
                  (nth 4 decoded)  ; month
                  (nth 3 decoded)  ; day
                  (nth 2 decoded)  ; hour
                  (nth 1 decoded)  ; minute
                  (nth 0 decoded))) ; second
      (error nil))))

(defconst orchid-parser--stub-label-width 10
  "Width of the event label column, including brackets and spacing.")

(defconst orchid-parser--stub-preview-width 44
  "Width of the preview column, including brackets.")

(defun orchid-parser--format-stub-with-timestamp (stub-text timestamp)
  "Format STUB-TEXT and TIMESTAMP in fixed-width columns."
  (let* ((formatted-timestamp (orchid-parser--format-timestamp timestamp))
         (parts (when (string-match "\\`\\(\\[[^]]+\\]\\)\\s-*\\(\\[[^]]*\\]\\)\\'" stub-text)
                 (list (match-string 1 stub-text) (match-string 2 stub-text))))
         (label (if (and parts (<= (string-width (car parts)) orchid-parser--stub-label-width))
                    (car parts) "[event]"))
         (preview (if parts (cadr parts) ""))
         (preview (if (string-match "\\.\\.\\.\\]\\'" preview)
                      (concat (substring preview 0 (match-beginning 0)) "]") preview))
         (content (if (and (> (length preview) 1)
                           (= (aref preview 0) ?\[)
                           (= (aref preview (1- (length preview))) ?\]))
                      (substring preview 1 -1) preview))
         (content (truncate-string-to-width
                   content (- orchid-parser--stub-preview-width 2) nil nil ""))
         (preview (concat "[" content
                          (make-string
                           (max 0 (- (- orchid-parser--stub-preview-width 2)
                                     (string-width content)))
                           ?\s)
                          "]"))
         (label-column (concat label (make-string (max 0 (- orchid-parser--stub-label-width (string-width label))) ?\s))))
    (concat label-column preview
            (when formatted-timestamp
              (concat "    [" formatted-timestamp "]")))))

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
