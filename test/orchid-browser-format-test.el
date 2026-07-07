;;; orchid-browser-format-test.el --- Tests for session browser formatting -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools, tests

;;; Code:

(require 'ert)
(require 'browser/orchid-browser-format)
(require 'orchid-test-helpers)

;;; orchid-browser-format-file-size

(ert-deftest orchid-browser-format-test-file-size-nil ()
  "Nil bytes returns N/A."
  (should (equal "N/A" (orchid-browser-format-file-size nil))))

(ert-deftest orchid-browser-format-test-file-size-bytes ()
  "Sub-1024 bytes shown as B."
  (should (equal "500 B" (orchid-browser-format-file-size 500))))

(ert-deftest orchid-browser-format-test-file-size-kb ()
  "1024-1048575 bytes shown as KB."
  (should (equal "1.0 KB" (orchid-browser-format-file-size 1024))))

(ert-deftest orchid-browser-format-test-file-size-mb ()
  "1 MB shown as MB."
  (should (equal "1.0 MB" (orchid-browser-format-file-size (* 1024 1024)))))

(ert-deftest orchid-browser-format-test-file-size-gb ()
  "1 GB shown as GB."
  (should (equal "1.00 GB" (orchid-browser-format-file-size (* 1024 1024 1024)))))

;;; orchid-browser-format-test-relative-time

(ert-deftest orchid-browser-format-test-modified-time-nil ()
  "Nil timestamp returns N/A."
  (should (equal "N/A" (orchid-browser-format-relative-time nil))))

(ert-deftest orchid-browser-format-test-modified-time-empty ()
  "Empty string returns N/A."
  (should (equal "N/A" (orchid-browser-format-relative-time ""))))

;;; orchid-browser-format-test-modified-time-format ()
;;   "Valid ISO timestamp returns DD-MM-YY HH:MM:SS."
;; Omitted: depends on parse-time library, not our logic.

(ert-deftest orchid-browser-format-test-modified-time-invalid ()
  "Malformed timestamp returns N/A via condition-case."
  (should (equal "N/A" (orchid-browser-format-relative-time "not-a-date"))))

;;; orchid-browser-format-persona

(ert-deftest orchid-browser-format-test-persona-present ()
  "Returns persona from session plist."
  (let ((session (list :persona "custom")))
    (should (equal "custom" (orchid-browser-format-persona session)))))

(ert-deftest orchid-browser-format-test-persona-absent ()
  "Returns 'default' when persona not in session."
  (let ((session (list :session-id "s1")))
    (should (equal "default" (orchid-browser-format-persona session)))))

;;; orchid-browser-format-workspace-name

(ert-deftest orchid-browser-format-test-workspace-name ()
  "Extracts last path component from working_dir."
  (let ((session (list :working_dir "/home/user/projects/my-app")))
    (should (equal "my-app" (orchid-browser-format-workspace-name session)))))

(ert-deftest orchid-browser-format-test-workspace-nil ()
  "Returns N/A when working_dir is nil."
  (let ((session (list :session-id "s1")))
    (should (equal "N/A" (orchid-browser-format-workspace-name session)))))

;;; orchid-browser-format-status

(ert-deftest orchid-browser-format-test-status-active-symbol ()
  "Active symbol returns ACTIVE."
  (should (equal "ACTIVE" (orchid-browser-format-status 'active))))

(ert-deftest orchid-browser-format-test-status-idle-symbol ()
  "Idle symbol returns IDLE."
  (should (equal "IDLE" (orchid-browser-format-status 'idle))))

(ert-deftest orchid-browser-format-test-status-plist-active-running ()
  "Plist with active buffer and running process returns ACTIVE•RUN."
  (should (equal "ACTIVE•RUN"
                 (orchid-browser-format-status
                  (list :buffer 'active :process-running t)))))

(ert-deftest orchid-browser-format-test-status-plist-active-only ()
  "Plist with active buffer but no process returns ACTIVE."
  (should (equal "ACTIVE"
                 (orchid-browser-format-status
                  (list :buffer 'active :process-running nil)))))

(ert-deftest orchid-browser-format-test-status-plist-idle-running ()
  "Plist with idle buffer but running process returns IDLE•RUN."
  (should (equal "IDLE•RUN"
                 (orchid-browser-format-status
                  (list :buffer 'idle :process-running t)))))

(ert-deftest orchid-browser-format-test-status-plist-idle-only ()
  "Plist with idle buffer and no process returns IDLE."
  (should (equal "IDLE"
                 (orchid-browser-format-status
                  (list :buffer 'idle :process-running nil)))))

(provide 'orchid-browser-format-test)

;;; orchid-browser-format-test.el ends here
