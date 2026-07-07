;;; orchid-parser-assistant.el --- Message event parser -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Parser for orchid `message` events (role=assistant and role=user).
;; Format: {type:"message", event_id, timestamp, message:{role, content}}

;;; Code:

(require 'parsers/orchid-parser-registry)
(require 'parsers/orchid-parser-utils)
(require 'core/orchid-collapsible)
(require 'core/orchid-faces)
(require 'json)

;; Forward declarations
(defvar orchid-log--restore-mode)

(defun orchid-parser--message (data)
  "Handle `message` log events from DATA (role=assistant or role=user).
Format: top-level :type=message, :timestamp, nested :message with :role and :content."
  (let* ((msg (plist-get data :message))
         (role (plist-get msg :role))
         (content (plist-get msg :content))
         (timestamp (plist-get data :timestamp)))
    (cond
     ;; User messages: only show in restore mode
     ((equal role "user")
      (if (and orchid-log--restore-mode content (not (string-empty-p content)))
          (let* ((clean (replace-regexp-in-string "\n" " " content))
                 (preview (if (> (length clean) 50)
                              (concat (substring clean 0 47) "...")
                            clean))
                 (base-stub (format "[User: %s]" preview))
                 (stub (orchid-parser--format-stub-with-timestamp base-stub timestamp)))
            (list :display (orchid-collapsible-create stub content t 'orchid-collapsible-user-stub-face)
                  :event-type "user"))
        (list :display "" :event-type "user")))
     ;; Assistant messages: collapsible
     ((equal role "assistant")
      (if (and content (not (string-empty-p content)))
          (let* ((clean (replace-regexp-in-string "\n" " " content))
                 (preview (if (> (length clean) 50)
                              (concat (substring clean 0 47) "...")
                            clean))
                 (base-stub (format "[Assistant: %s]" preview))
                 (stub (orchid-parser--format-stub-with-timestamp base-stub timestamp))
                 (detail-fn (lambda ()
                              (concat (propertize "Assistant: " 'face 'orchid-chat-assistant-face)
                                      content))))
            (list :display (orchid-collapsible-create-lazy stub detail-fn t)
                  :event-type "assistant"
                  :has-text t))
        (list :display "" :event-type "assistant" :has-text nil)))
     (t (list :display "" :event-type "message")))))

;; Register handler
(orchid-parser-register "message" #'orchid-parser--message)

(provide 'parsers/orchid-parser-assistant)

;;; orchid-parser-assistant.el ends here
