;;; orchid-chat-header-test.el --- Test chat header functionality -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools, tests

;;; Commentary:

;; Tests for chat buffer header metadata functionality.

;;; Code:

(require 'ert)
(require 'orchid-chat)
(require 'session/orchid-session)
(require 'orchid-test-helpers)

(ert-deftest orchid-chat-test-header-metadata-format ()
  "Header metadata contains workspace and persona from session."
  (let* ((orchid-session--registry nil)
         (session (orchid-test-make-session
                   (list :id "test-123"
                         :label "test-session"
                         :persona "developer"
                         :working_dir "/home/user/project"))))
    (orchid-session--update-registry (list session))
    (let ((metadata (orchid-chat--format-header-metadata "test-123")))
      (should (string-match-p "Persona:.*developer" metadata))
      (should (string-match-p "Workspace:.*project" metadata))
      (should (string-match-p "\\[CONFIG\\]" metadata)))))

(ert-deftest orchid-chat-test-header-no-metadata-for-pending ()
  "Pending sessions don't show workspace or persona metadata."
  (with-temp-buffer
    (orchid-chat-mode)
    (orchid-chat--setup-buffer "pending" "new-developer")
    (let ((content (buffer-string)))
      (should-not (string-match-p "Persona:" content))
      (should-not (string-match-p "Workspace:" content)))))

(ert-deftest orchid-chat-test-header-with-metadata ()
  "Real sessions produce metadata with workspace and persona."
  (let* ((orchid-session--registry nil)
         (session (orchid-test-make-session
                   (list :id "test-456"
                         :label "dev-session"
                         :persona "developer"
                         :working_dir "/home/dev/code"))))
    (orchid-session--update-registry (list session))
    (let ((metadata (orchid-chat--format-header-metadata "test-456")))
      (should (string-match-p "Persona:.*developer" metadata))
      (should (string-match-p "Workspace:.*code" metadata)))))

(provide 'orchid-chat-header-test)

;;; orchid-chat-header-test.el ends here
