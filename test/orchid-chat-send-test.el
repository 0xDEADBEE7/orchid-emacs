;;; orchid-chat-send-test.el --- Tests for orchid-chat-send -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools, tests

;;; Code:

(require 'ert)
(require 'orchid-test-helpers)
(require 'chat/orchid-chat-send)

;;; orchid-chat--send-to-existing-session

(ert-deftest orchid-chat-send-test-send-to-existing-calls-core ()
  "send-to-existing-session calls orchid-core-send with session id."
  (orchid-test-with-mocks
    (let ((buf (generate-new-buffer "*orchid-send-test*")))
      (unwind-protect
          (with-current-buffer buf
            (setq-local orchid-chat--session-id "sess-123")
            (setq-local orchid-chat--assistant-cursor (point-marker))
            (orchid-chat--send-to-existing-session "hello")
            (should (= 1 (length orchid-test-mock-cli-calls)))
            (let ((args (car orchid-test-mock-cli-calls)))
              (should (member "--id" args))
              (should (member "sess-123" args))
              (should (member "hello" args))))
        (kill-buffer buf)))))

(ert-deftest orchid-chat-send-test-send-to-existing-error-path ()
  "send-to-existing-session error result calls system message handler."
  (let ((system-messages nil))
    (cl-letf (((symbol-function 'orchid-core-cli-available-p) (lambda () t))
              ((symbol-function 'orchid-core--execute-internal-async)
               (lambda (_args callback)
                 (funcall callback (list :success nil :error "Connection refused" :exit-code 1))))
              ((symbol-function 'orchid-chat-insert-system-message)
               (lambda (msg) (push msg system-messages))))
      (let ((buf (generate-new-buffer "*orchid-send-test-err*")))
        (unwind-protect
            (with-current-buffer buf
              (setq-local orchid-chat--session-id "sess-err")
              (setq-local orchid-chat--assistant-cursor (point-marker))
              (orchid-chat--send-to-existing-session "oops")
              (should (= 1 (length system-messages)))
              (should (string-match-p "Connection refused" (car system-messages))))
          (kill-buffer buf))))))


(provide 'orchid-chat-send-test)

;;; orchid-chat-send-test.el ends here
