;;; orchid-parser-registry.el --- Parser registry for Orchid -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Central registry for log event parsers.
;; Each event type has its own handler file in lisp/parsers/.

;;; Code:

(require 'json)

;;; Event Handler Registry

(defvar orchid-parser--handlers (make-hash-table :test 'equal)
  "Hash table mapping event type strings to handler functions.
Handler functions take parsed JSON data and return a plist:
  (:display TEXT :event-type TYPE)")

(defun orchid-parser-register (event-type handler-fn)
  "Register HANDLER-FN for EVENT-TYPE.
EVENT-TYPE is a string like \"message\", \"tool_call\", or \"tool_result\".
HANDLER-FN takes parsed JSON data and returns:
  (:display TEXT :event-type TYPE)
where TEXT is formatted output (empty string to filter)."
  (puthash event-type handler-fn orchid-parser--handlers))

(defun orchid-parser-parse-json-data (data line)
  "Parse already-parsed JSON DATA and dispatch to appropriate handler.
LINE is the original JSON string for error messages.
Returns plist with :display and :event-type, or nil if not JSON.
This is an optimization to avoid re-parsing JSON."
  (condition-case nil
      (let* ((type-raw (plist-get data :type))
             (type (when type-raw (format "%s" type-raw))))

        (if type
            (let ((handler (gethash type orchid-parser--handlers)))
              (if handler
                  ;; Use registered handler
                  (funcall handler data)
                ;; Unrecognized event: show raw JSON
                (list :display (format "[Unhandled event: %s]\n%s\n\n" type line)
                      :event-type type)))
          ;; No type field: show raw JSON
          (list :display (format "[Event with no type]\n%s\n\n" line)
                :event-type "unknown")))
    (error nil)))

(defun orchid-parser-parse-json (line)
  "Parse JSON log LINE and dispatch to appropriate handler.
Returns plist with :display and :event-type, or nil if not JSON."
  (condition-case nil
      (let* ((json-object-type 'plist)
             (json-array-type 'list)
             (json-key-type 'keyword)
             (data (json-read-from-string line)))
        (orchid-parser-parse-json-data data line))
    (error nil)))

(provide 'parsers/orchid-parser-registry)

;;; orchid-parser-registry.el ends here
