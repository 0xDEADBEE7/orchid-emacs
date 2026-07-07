;;; orchid-parser-tool-result.el --- Tool result event parser -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Parser for orchid `tool_result` events.
;; Format: {type:"tool_result", event_id, timestamp, tool_result:{call_id, content}}
;; content is either a string (single result) or an object mapping paths to
;; string content or {error:"..."} (batch fs_read format).

;;; Code:

(require 'parsers/orchid-parser-registry)
(require 'parsers/orchid-parser-utils)
(require 'core/orchid-collapsible)

(defun orchid-parser--tool-result-format-map (content-map)
  "Format CONTENT-MAP (plist of path→content or path→{error}) as nested collapsibles."
  (let ((parts '())
        (rest content-map))
    (while rest
      (let* ((key (pop rest))
             (val (pop rest))
             (path (substring (symbol-name key) 1)) ; strip leading ":"
             (stub (format "[%s]" path))
             (detail (if (and (listp val) (plist-get val :error))
                         (concat "[error] " (plist-get val :error) "\n")
                       (concat (if (stringp val) val (format "%S" val)) "\n"))))
        (push (orchid-collapsible-create stub detail t) parts)))
    (string-join (nreverse parts) "\n")))

(defun orchid-parser--tool-result (data)
  "Handle tool_result events from DATA.
Displays as a collapsible stub with full content on expand."
  (let* ((result-obj (or (plist-get data :tool_result) data))
         (call-id (plist-get result-obj :call_id))
         (content (plist-get result-obj :content))
         (timestamp (plist-get data :timestamp))
         (base-stub "[---------------------------------------------------------]")
         (stub (orchid-parser--format-stub-with-timestamp base-stub timestamp)))
    (cond
     ((not content)
      (list :display "" :event-type "tool_result"))
     ((and (stringp content) (string-empty-p content))
      (list :display "" :event-type "tool_result"))
     ((listp content)
      (let ((detail-fn (lambda ()
                         (concat "  Call ID: " (or call-id "") "\n"
                                 "  Results:\n"
                                 (orchid-parser--tool-result-format-map content)))))
        (list :display (orchid-collapsible-create-lazy stub detail-fn t)
              :event-type "tool_result")))
     (t
      (let ((detail (concat "  Call ID: " (or call-id "") "\n"
                            "  Result:\n"
                            (mapconcat (lambda (line) (concat "  " line))
                                       (split-string content "\n")
                                       "\n"))))
        (list :display (orchid-collapsible-create stub detail t)
              :event-type "tool_result"))))))

;; Register handler
(orchid-parser-register "tool_result" #'orchid-parser--tool-result)

(provide 'parsers/orchid-parser-tool-result)

;;; orchid-parser-tool-result.el ends here
