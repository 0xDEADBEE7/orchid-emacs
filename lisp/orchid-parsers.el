;;; orchid-parsers.el --- Load all parsers -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Loads all parser modules and provides the parser list for orchid-log.el.
;; To add a new parser:
;;   1. Create lisp/parsers/orchid-parser-EVENTNAME.el
;;   2. Require it below using parsers/ prefix
;;   3. Parser auto-registers itself on load

;;; Code:

(require 'parsers/orchid-parser-registry)
(require 'parsers/orchid-parser-utils)
(require 'parsers/orchid-parser-assistant)   ; registers "message" (role=user|assistant)
(require 'parsers/orchid-parser-tool-use)    ; registers "tool_call"
(require 'parsers/orchid-parser-tool-result) ; registers "tool_result"

;;; Parser List (for orchid-log.el)

(defvar orchid-log-parsers
  '(orchid-parser-parse-json)
  "List of parser functions to try in order.
Currently just JSON parser which dispatches to registered handlers.")

(provide 'orchid-parsers)

;;; orchid-parsers.el ends here
