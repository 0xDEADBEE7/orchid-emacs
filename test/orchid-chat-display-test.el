;;; orchid-chat-display-test.el --- Tests for orchid-chat-display -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools, tests

;;; Code:

(require 'ert)
(require 'orchid-test-helpers)
(require 'chat/orchid-chat-display)

;;; orchid-chat-insert-log-line

(ert-deftest orchid-chat-display-test-insert-log-line-inserts-text ()
  "orchid-chat-insert-log-line inserts display text into buffer."
  (let ((buf (generate-new-buffer "*orchid-display-test*")))
    (unwind-protect
        (with-current-buffer buf
          (setq-local orchid-chat--assistant-cursor (point-marker))
          (cl-letf (((symbol-function 'orchid-chat--ensure-assistant-cursor) #'ignore))
            (orchid-chat-insert-log-line buf (list :display "hello world" :event-type "assistant"))
            (should (string-match-p "hello world" (buffer-string)))))
      (kill-buffer buf))))

(ert-deftest orchid-chat-display-test-insert-log-line-skips-empty ()
  "orchid-chat-insert-log-line skips events with empty display text."
  (let ((buf (generate-new-buffer "*orchid-display-empty-test*")))
    (unwind-protect
        (with-current-buffer buf
          (setq-local orchid-chat--assistant-cursor (point-marker))
          (cl-letf (((symbol-function 'orchid-chat--ensure-assistant-cursor) #'ignore))
            (orchid-chat-insert-log-line buf (list :display "" :event-type "assistant"))
            (should (string-empty-p (buffer-string)))))
      (kill-buffer buf))))

(ert-deftest orchid-chat-display-test-insert-log-line-nil-event ()
  "orchid-chat-insert-log-line handles nil event gracefully."
  (let ((buf (generate-new-buffer "*orchid-display-nil-test*")))
    (unwind-protect
        (with-current-buffer buf
          (orchid-chat-insert-log-line buf nil))
      (kill-buffer buf))))

(ert-deftest orchid-chat-display-test-insert-log-line-dead-buffer ()
  "orchid-chat-insert-log-line ignores dead buffer."
  (let ((buf (generate-new-buffer "*orchid-display-dead-test*")))
    (kill-buffer buf)
    (orchid-chat-insert-log-line buf (list :display "should be ignored" :event-type "assistant"))))

(provide 'orchid-chat-display-test)

;;; orchid-chat-display-test.el ends here
