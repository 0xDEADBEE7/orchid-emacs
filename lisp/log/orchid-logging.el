;;; orchid-logging.el --- Simple logging for Orchid -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Simple logging to stop message spam.
;; All logs go to *Orchid Log* buffer instead of minibuffer.

;;; Code:

(defvar orchid-log-buffer "*Orchid Log*"
  "Buffer name for Orchid logs.")

(defun orchid-log (format-string &rest args)
  "Log message to *Orchid Log* buffer.
FORMAT-STRING and ARGS work like `format'."
  (with-current-buffer (get-buffer-create orchid-log-buffer)
    (goto-char (point-max))
    (insert (format-time-string "[%H:%M:%S] "))
    (insert (apply #'format format-string args))
    (insert "\n")))

(provide 'log/orchid-logging)

;;; orchid-logging.el ends here
