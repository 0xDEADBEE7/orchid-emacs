;;; orchid-log-parse.el --- Log line parsing for Orchid -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Log line parsing functions extracted from orchid-log.el.
;; Provides both the legacy parser-list interface (orchid-log-parse-line) and
;; the single-pass parser used by live monitoring (orchid-log--parse-line-with-id).

;;; Code:

(require 'json)
(require 'orchid-parsers)
(require 'parsers/orchid-parser-registry)
(require 'log/orchid-logging)

(defun orchid-log-parser-raw (line)
  "Pass through LINE unmodified as raw event."
  (list :display line :event-type "raw"))

(defun orchid-log-parse-line (line)
  "Parse LINE using registered parsers.
Returns a plist with :display and :event-type keys, or nil if no parser matched."
  (catch 'parsed
    (dolist (parser orchid-log-parsers)
      (let ((result (funcall parser line)))
        (when result
          (if (listp result)
              (throw 'parsed result)
            (throw 'parsed (list :display result :event-type "unknown"))))))
    nil))

(defun orchid-log--parse-line-with-id (line)
  "Parse LINE in a single pass, returning all fields needed for live monitoring.
Returns a plist with :event-id, :type, :timestamp, :operation, and :parsed.
Returns nil if the line cannot be parsed as JSON."
  (condition-case nil
      (let* ((json-object-type 'plist)
             (json-array-type 'list)
             (json-key-type 'keyword)
             (json-data (if (fboundp 'json-parse-string)
                            (json-parse-string line :object-type 'plist :array-type 'list)
                          (json-read-from-string line)))
             (type (plist-get json-data :type))
             (event-id (plist-get json-data :event_id))
             (timestamp (plist-get json-data :timestamp)))
        (let ((parsed (orchid-parser-parse-json-data json-data line)))
          (when parsed
            (list :event-id event-id
                  :type type
                  :timestamp timestamp
                  :parsed parsed))))
    (error nil)))

(provide 'log/orchid-log-parse)

;;; orchid-log-parse.el ends here
