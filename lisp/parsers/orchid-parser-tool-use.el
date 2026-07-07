;;; orchid-parser-tool-use.el --- Tool call event parser -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Parser for orchid `tool_call` events.
;; Format: {type:"tool_call", event_id, timestamp, tool_call:{calls:[{id, name, input}]}}

;;; Code:

(require 'parsers/orchid-parser-registry)
(require 'parsers/orchid-parser-utils)
(require 'core/orchid-collapsible)
(require 'json)

(defun orchid-parser--format-tool-args (tool-name args)
  "Format ARGS for TOOL-NAME in a readable way.
Orchid tool args use: bash → cmd, fs_read → path."
  (cond
   ((equal tool-name "bash")
    (let ((cmd (plist-get args :cmd)))
      (if (and cmd (string-match-p "\n" cmd))
          (concat "  Command:\n"
                  (mapconcat (lambda (line) (concat "    " line))
                             (split-string cmd "\n") "\n"))
        (concat "  Command: " (or cmd "")))))

   ((equal tool-name "fs_read")
    (let ((paths (plist-get args :paths))
          (path (plist-get args :path))
          (offset (plist-get args :offset))
          (limit (plist-get args :limit)))
      (if paths
          (concat "  Paths:\n"
                  (mapconcat (lambda (p) (concat "    " p)) paths "\n"))
        (concat "  Path: " (or path "")
                (when offset (format "\n  Offset: %s" offset))
                (when limit (format "\n  Limit: %s" limit))))))

   ((equal tool-name "fs_edit")
    (let ((path (plist-get args :path))
          (old-string (plist-get args :old_string))
          (new-string (plist-get args :new_string)))
      (concat "  Path: " (or path "") "\n"
              (orchid-parser--format-edit-diff old-string new-string))))

   (t
    (concat "  Args: " (json-encode args)))))

(defun orchid-parser--format-call-stub (name input)
  "Format a short stub label for a single call with NAME and INPUT args."
  (cond
   ((equal name "bash")
    (let ((cmd (plist-get input :cmd)))
      (if cmd
          (format "[bash] [%s]"
                  (let ((flat (replace-regexp-in-string "\n" " " cmd)))
                    (if (> (length flat) 45)
                        (concat (substring flat 0 42) "...")
                      flat)))
        "[bash]")))
   ((equal name "fs_read")
    (let ((paths (plist-get input :paths))
          (path (plist-get input :path)))
      (if paths
          (format "[read] [%d files]" (length paths))
        (format "[read] [%s]"
                (orchid-parser--truncate-path-left (or path "") 45)))))
   ((equal name "fs_edit")
    (format "[edit] [%s]"
            (orchid-parser--truncate-path-left (or (plist-get input :path) "") 45)))
   (t (format "[%s]" name))))

;;; Parser

(defun orchid-parser--tool-call (data)
  "Handle tool_call events from DATA.
New format: nested :tool_call with :calls array of {id, name, input}."
  (let* ((tool-call-obj (plist-get data :tool_call))
         (calls (when tool-call-obj (plist-get tool-call-obj :calls)))
         (timestamp (plist-get data :timestamp)))
    (when (and calls (listp calls) (> (length calls) 0))
      (let* ((parts
              (mapcar
               (lambda (call)
                 (let* ((call-id (plist-get call :id))
                        (name (plist-get call :name))
                        (input (plist-get call :input))
                        (stub-text (orchid-parser--format-call-stub name input))
                        (stub (orchid-parser--format-stub-with-timestamp stub-text timestamp))
                        (detail-fn (lambda ()
                                     (concat "  Tool: " (or name "") "\n"
                                             "  ID: " (or call-id "") "\n"
                                             (orchid-parser--format-tool-args name input)))))
                   (orchid-collapsible-create-lazy stub detail-fn t)))
               calls)))
        (list :display (string-join parts "\n")
              :event-type "tool_call")))))

;; Register handler
(orchid-parser-register "tool_call" #'orchid-parser--tool-call)

(provide 'parsers/orchid-parser-tool-use)

;;; orchid-parser-tool-use.el ends here
