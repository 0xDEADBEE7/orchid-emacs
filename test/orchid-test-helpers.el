;;; orchid-test-helpers.el --- Test helpers for Orchid -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools, tests

;;; Code:

(require 'ert)

;;; Test Fixtures

(defvar orchid-test-temp-dir nil
  "Temporary directory for test files.")

(defun orchid-test-setup ()
  "Set up test environment."
  (setq orchid-test-temp-dir (make-temp-file "orchid-test-" t))
  ;; Save original values
  (put 'orchid-test 'original-cli-path orchid-core-cli-path))

(defun orchid-test-teardown ()
  "Clean up test environment."
  (when orchid-test-temp-dir
    (delete-directory orchid-test-temp-dir t))
  ;; Restore original values
  (setq orchid-core-cli-path (get 'orchid-test 'original-cli-path)))

;;; Mock Functions

(defvar orchid-test-mock-cli-calls nil
  "List of CLI calls made during test.")

(defun orchid-test-mock-cli-execute (args)
  "Mock CLI execution with ARGS."
  (push args orchid-test-mock-cli-calls)
  (list :success t
        :data '(:sessions ())
        :raw ""
        :exit-code 0
        :duration 0.1))

(defmacro orchid-test-with-mocks (&rest body)
  "Execute BODY with mocked CLI execution functions."
  `(let ((orchid-test-mock-cli-calls nil))
     (cl-letf (((symbol-function 'orchid-core-cli-available-p) (lambda () t))
               ((symbol-function 'orchid-core--execute-internal-sync)
                #'orchid-test-mock-cli-execute)
               ((symbol-function 'orchid-core--execute-internal-async)
                (lambda (args callback)
                  (funcall callback (orchid-test-mock-cli-execute args)))))
       ,@body)))
;;; Test Data Generators

(defun orchid-test-make-session (&optional overrides)
  "Create test session plist matching the real CLI/registry format.
Uses :id key as the session identifier."
  (let ((session (list :id "test-session-123"
                       :label "test-session"
                       :working_dir "/tmp/test"
                       :persona "default"
                       :created_at "2024-01-01T00:00:00Z"
                       :updated_at "2024-01-01T00:00:00Z")))
    (when overrides
      (cl-loop for (key val) on overrides by #'cddr
               do (setq session (plist-put session key val))))
    session))

(defun orchid-test-make-sessions (count)
  "Create COUNT test sessions."
  (cl-loop for i from 1 to count
           collect (orchid-test-make-session
                    (list :id (format "session-%d" i)
                          :label (format "test-%d" i)))))

;;; Assertion Helpers

(defmacro orchid-test-should-contain (substring string)
  "Assert that STRING contains SUBSTRING."
  `(should (string-match-p (regexp-quote ,substring) ,string)))

(defun orchid-test-buffer-content (buffer)
  "Get content of BUFFER as string."
  (with-current-buffer buffer
    (buffer-substring-no-properties (point-min) (point-max))))

;;; File Helpers

(defun orchid-test-create-temp-file (content &optional name)
  "Create temporary file with CONTENT and optional NAME."
  (let ((file (expand-file-name (or name (make-temp-name "test-"))
                                orchid-test-temp-dir)))
    (with-temp-file file
      (insert content))
    file))

(defun orchid-test-read-file (file)
  "Read contents of FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(provide 'orchid-test-helpers)

;;; orchid-test-helpers.el ends here
