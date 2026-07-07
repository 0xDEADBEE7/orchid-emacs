;;; orchid-session-test.el --- Unit tests for orchid-session -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools, tests

;;; Code:

(require 'ert)
(require 'session/orchid-session)
(require 'orchid-test-helpers)

;;; Session Registry Tests

(ert-deftest orchid-session-test-update-registry ()
  "Update registry with N sessions; registry length must equal N."
  (let ((orchid-session--registry nil)
        (sessions (orchid-test-make-sessions 3)))
    (orchid-session--update-registry sessions)
    (should (= 3 (length orchid-session--registry)))))

(ert-deftest orchid-session-test-get-by-id ()
  "Get session by ID returns the matching session."
  (let ((orchid-session--registry nil)
        (session (orchid-test-make-session)))
    (orchid-session--update-registry (list session))
    (let ((found (orchid-session-get "test-session-123")))
      (should found)
      (should (equal "test-session-123" (plist-get found :id))))))

(ert-deftest orchid-session-test-get-by-label ()
  "Get session by label returns the matching session."
  (let ((orchid-session--registry nil)
        (session (orchid-test-make-session)))
    (orchid-session--update-registry (list session))
    (let ((found (orchid-session-get "test-session")))
      (should found)
      (should (equal "test-session" (plist-get found :label))))))

(ert-deftest orchid-session-test-list ()
  "List returns all sessions in the registry."
  (let ((orchid-session--registry nil)
        (sessions (orchid-test-make-sessions 5)))
    (orchid-session--update-registry sessions)
    (should (= 5 (length (orchid-session-list))))))

;;; Session State Tests

(ert-deftest orchid-session-test-buffer-associations ()
  "Session buffer associations are stored and retrieved correctly."
  (let* ((orchid-session--registry nil)
         (session (orchid-test-make-session))
         (test-buffer (generate-new-buffer " *test*")))
    (orchid-session--update-registry (list session))
    (let ((stored (orchid-session-get "test-session-123")))
      (plist-put stored :chat-buffer test-buffer)
      (should (equal test-buffer
                     (orchid-session-get-chat-buffer "test-session-123"))))
    (kill-buffer test-buffer)))

(ert-deftest orchid-session-test-monitoring-status ()
  "Monitoring status is false by default; true after setting :monitoring-p."
  (let* ((orchid-session--registry nil)
         (session (orchid-test-make-session)))
    (orchid-session--update-registry (list session))
    (should-not (orchid-session-monitoring-p "test-session-123"))
    (plist-put (orchid-session-get "test-session-123") :monitoring-p t)
    (should (orchid-session-monitoring-p "test-session-123"))))

;;; Session Cleanup Tests

(ert-deftest orchid-session-test-cleanup-dead-buffers ()
  "Cleanup removes dead buffer references from registry."
  (let* ((orchid-session--registry nil)
         (session (orchid-test-make-session))
         (test-buffer (generate-new-buffer " *test*")))
    (orchid-session--update-registry (list session))
    (plist-put (orchid-session-get "test-session-123") :chat-buffer test-buffer)
    (kill-buffer test-buffer)
    (orchid-session-cleanup)
    (should-not (orchid-session-get-chat-buffer "test-session-123"))))

;;; Current Session Tests

(ert-deftest orchid-session-test-current-session ()
  "Current session tracking works per-buffer."
  (with-temp-buffer
    (should-not (orchid-session-current))
    (orchid-session-set-current "test-123")
    (should (equal "test-123" (orchid-session-current)))))

(provide 'orchid-session-test)

;;; orchid-session-test.el ends here
