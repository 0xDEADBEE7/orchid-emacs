;;; orchid-chat-session-test.el --- Tests for orchid-chat-session -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools, tests

;;; Code:

(require 'ert)
(require 'session/orchid-session)
(require 'orchid-test-helpers)
(require 'chat/orchid-chat-session)

(ert-deftest orchid-chat-session-format-buffer-name-basic ()
  "orchid-chat--format-buffer-name produces expected format."
  (let* ((session (orchid-test-make-session
                   (list :id "abc12345"
                         :persona "developer"
                         :working_dir "/home/user/myproject")))
         (name (orchid-chat--format-buffer-name "abc12345" session)))
    (should (stringp name))
    (should (string-match-p "\\*orchid-chat-" name))
    (should (string-match-p "developer" name))
    (should (string-match-p "myproject" name))
    ;; Last 5 chars of session id
    (should (string-match-p "12345" name))))

(ert-deftest orchid-chat-session-format-buffer-name-ends-with-stars ()
  "Buffer name is wrapped in *..."
  (let* ((session (orchid-test-make-session))
         (name (orchid-chat--format-buffer-name "test-session-123" session)))
    (should (string-prefix-p "*" name))
    (should (string-suffix-p "*" name))))

(ert-deftest orchid-chat-session-format-buffer-name-no-workspace ()
  "Buffer name handles missing workspace gracefully."
  (let* ((session (list :id "abc12345" :persona "developer"))
         (name (orchid-chat--format-buffer-name "abc12345" session)))
    (should (stringp name))
    (should (string-match-p "none" name))))

(ert-deftest orchid-chat-session-open-new-creates-buffer-in-chat-mode ()
  "orchid-chat-open-new creates a live buffer in orchid-chat-mode."
  (require 'orchid-chat)
  (cl-letf (((symbol-function 'orchid-core-cli-available-p) (lambda () t))
            ((symbol-function 'orchid-core--execute-internal-async)
             (lambda (_args _callback) nil)))
    (let ((buf (orchid-chat-open-new "developer")))
      (unwind-protect
          (progn
            (should (buffer-live-p buf))
            (with-current-buffer buf
              (should (eq major-mode 'orchid-chat-mode))))
        (kill-buffer buf)))))

(ert-deftest orchid-chat-session-open-new-calls-create ()
  "orchid-chat-open-new issues an orchid create command."
  (require 'orchid-chat)
  (let (captured-args)
    (cl-letf (((symbol-function 'orchid-core-cli-available-p) (lambda () t))
              ((symbol-function 'orchid-core--execute-internal-async)
               (lambda (args _callback)
                 (setq captured-args args))))
      (let ((buf (orchid-chat-open-new "developer")))
        (unwind-protect
            (should (equal (car captured-args) "create"))
          (kill-buffer buf))))))

(provide 'orchid-chat-session-test)

;;; orchid-chat-session-test.el ends here
