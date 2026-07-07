;;; orchid-log-test.el --- Unit tests for orchid-log -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools, tests

;;; Code:

(require 'ert)
(require 'orchid-log)
(require 'log/orchid-log-registry)

;;; Parser Tests

(ert-deftest orchid-log-test-parser-raw ()
  "Test raw pass-through parser returns plist with :display."
  (let ((result (orchid-log-parser-raw "test line")))
    (should (equal "test line" (plist-get result :display)))
    (should (equal "raw" (plist-get result :event-type)))))

(ert-deftest orchid-log-test-parse-line ()
  "Test line parsing returns plist with :display and :event-type."
  (let* ((orchid-log-parsers '(orchid-log-parser-raw))
         (result (orchid-log-parse-line "test")))
    (should (equal "test" (plist-get result :display)))
    (should (stringp (plist-get result :event-type)))))

;;; Registry Tests

(ert-deftest orchid-log-test-monitoring-registry ()
  "Monitoring registry: not monitoring before register, monitoring after."
  (let ((orchid-log--registry nil))
    (should-not (orchid-log-monitoring-p "test-session"))
    (let ((buf (generate-new-buffer " *test-log*")))
      (orchid-log--register "test-session" "/tmp/test.log" buf nil)
      (should (orchid-log-monitoring-p "test-session"))
      (kill-buffer buf)
      (setq orchid-log--registry nil))))

(ert-deftest orchid-log-test-get-buffer ()
  "orchid-log-get-buffer returns the buffer registered for a session."
  (let ((orchid-log--registry nil)
        (test-buffer (generate-new-buffer " *test-log*")))
    (orchid-log--register "test-session" "/tmp/test.log" test-buffer nil)
    (should (equal test-buffer (orchid-log-get-buffer "test-session")))
    (kill-buffer test-buffer)
    (setq orchid-log--registry nil)))

(provide 'orchid-log-test)

;;; orchid-log-test.el ends here
