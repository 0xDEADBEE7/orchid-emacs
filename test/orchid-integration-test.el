;;; orchid-integration-test.el --- Integration test: send message and receive response -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools, tests

;;; Commentary:

;; End-to-end integration test for the send → response pipeline.
;; Calls the real orchid CLI: creates a session, sends a message,
;; polls conversation.jsonl for an assistant reply within a timeout.
;;
;; Skipped automatically when the orchid CLI is not installed.
;; Run manually or in CI with: make integration

;;; Code:

(require 'ert)
(require 'core/orchid-core)
(require 'json)

;;; Helpers

(defun orchid-itest--poll-for-response (session-id timeout-secs)
  "Poll conversation.jsonl for SESSION-ID until an assistant message appears.
Returns the assistant message text, or nil if TIMEOUT-SECS elapses."
  (let* ((conv-path (expand-file-name
                     (format "~/.config/orchid/conversations/%s/conversation.jsonl"
                             session-id)))
         (deadline (+ (float-time) timeout-secs))
         (result nil))
    (while (and (not result) (< (float-time) deadline))
      (when (file-exists-p conv-path)
        (with-temp-buffer
          (insert-file-contents conv-path)
          (goto-char (point-min))
          (while (and (not result) (not (eobp)))
            (let* ((line (buffer-substring-no-properties
                          (line-beginning-position) (line-end-position)))
                   (event (condition-case nil
                              (let ((json-object-type 'plist)
                                    (json-array-type 'list)
                                    (json-key-type 'keyword))
                                (json-read-from-string line))
                            (error nil))))
              (when (and event
                         (equal (plist-get event :type) "message")
                         (equal (plist-get (plist-get event :message) :role)
                                "assistant"))
                (setq result (plist-get (plist-get event :message) :content))))
            (forward-line 1))))
      (unless result
        (sleep-for 0.5)))
    result))

(defun orchid-itest--create-session ()
  "Create a fresh session via orchid-core-create.
Returns session-id string or signals an error."
  (let* ((result (orchid-core-create))
         (data (plist-get result :data)))
    (unless (plist-get result :success)
      (error "orchid create failed: %s" (plist-get result :error)))
    (or (plist-get data :id)
        (error "orchid create returned no id: %S" data))))

(defun orchid-itest--send-message (session-id message)
  "Send MESSAGE to SESSION-ID.  Signals if the send command fails."
  (let* ((send-result nil)
         (done nil))
    (orchid-core-send
     message session-id
     :callback (lambda (r) (setq send-result r done t)))
    ;; Wait up to 10s for the async callback (orchid send returns immediately)
    (let ((deadline (+ (float-time) 10)))
      (while (and (not done) (< (float-time) deadline))
        (sleep-for 0.1)))
    (unless done
      (error "orchid send timed out waiting for CLI response"))
    (unless (plist-get send-result :success)
      (error "orchid send failed: %s" (plist-get send-result :error)))
    send-result))

(defun orchid-itest--delete-session (session-id)
  "Best-effort delete SESSION-ID; never raises."
  (condition-case nil
      (orchid-core-delete session-id)
    (error nil)))

;;; Tests

(ert-deftest orchid-itest-send-and-receive-response ()
  "Send a message via orchid-core-send and verify an assistant reply appears.
This test calls the real orchid CLI and is skipped when it is unavailable."
  (skip-unless (orchid-core-cli-available-p))
  (let ((session-id nil))
    (unwind-protect
        (progn
          ;; 1. Create session
          (setq session-id (orchid-itest--create-session))
          (should (stringp session-id))
          (should (> (length session-id) 0))

          ;; 2. Send a message that produces a short, deterministic reply
          (orchid-itest--send-message session-id "Reply with exactly the word: PONG")

          ;; 3. Poll for assistant response (60 second timeout)
          (let ((response (orchid-itest--poll-for-response session-id 60)))
            (should (stringp response))
            (should (> (length response) 0))))

      ;; Cleanup
      (when session-id
        (orchid-itest--delete-session session-id)))))

(provide 'orchid-integration-test)

;;; orchid-integration-test.el ends here
