;;; orchid-parser-test.el --- Tests for orchid parser system -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools, tests

;;; Code:

(require 'ert)
(require 'parsers/orchid-parser-registry)
(require 'orchid-parsers)
(require 'parsers/orchid-parser-utils)
(require 'parsers/orchid-parser-tool-use)

(ert-deftest orchid-parser-parse-json-message-assistant ()
  "assistant event returns :display and :event-type."
  (let* ((json "{\"type\":\"assistant\",\"uuid\":\"u1\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Hello world\"}]}}")
         (result (orchid-parser-parse-json json)))
    (should result)
    (should (plist-get result :display))
    (should (plist-get result :event-type))))

(ert-deftest orchid-parser-parse-json-message-type ()
  "\"message\" event with flat role/content string (real log format)."
  (let* ((json "{\"type\":\"message\",\"role\":\"assistant\",\"content\":\"Hello world\"}")
         (result (orchid-parser-parse-json json)))
    (should result)
    (should (plist-get result :display))
    (should (string= (plist-get result :event-type) "assistant"))))

(ert-deftest orchid-parser-parse-json-message-empty-content ()
  "assistant event with empty content array returns empty :display string."
  (let* ((json "{\"type\":\"assistant\",\"uuid\":\"u2\",\"message\":{\"content\":[]}}")
         (result (orchid-parser-parse-json json)))
    (should result)
    (should (string= "" (plist-get result :display)))))

(ert-deftest orchid-parser-parse-json-unknown-type-returns-raw ()
  "Unknown event type returns display with raw JSON line."
  (let* ((json "{\"type\":\"orchid_unknown_xyz\",\"data\":\"test\"}")
         (result (orchid-parser-parse-json json)))
    (should result)
    (should (string-match-p "orchid_unknown_xyz" (plist-get result :display)))))

(ert-deftest orchid-parser-parse-json-no-type-returns-display ()
  "JSON with no type field returns display with fallback text."
  (let* ((json "{\"content\":\"no type here\"}")
         (result (orchid-parser-parse-json json)))
    (should result)
    (should (plist-get result :display))
    (should (string= (plist-get result :event-type) "unknown"))))

(ert-deftest orchid-parser-parse-json-invalid-returns-nil ()
  "Invalid JSON returns nil."
  (let ((result (orchid-parser-parse-json "not json at all")))
    (should-not result)))

(ert-deftest orchid-parser-register-and-dispatch ()
  "Registering a handler causes it to be called for its event type."
  (let ((orchid-parser--handlers (make-hash-table :test 'equal))
        (called-with nil))
    (orchid-parser-register
     "test_event"
     (lambda (data)
       (setq called-with data)
       (list :display "test output" :event-type "test_event")))
    (let* ((json "{\"type\":\"test_event\",\"value\":42}")
           (result (orchid-parser-parse-json json)))
      (should result)
      (should (string= (plist-get result :display) "test output"))
      (should called-with))))

(ert-deftest orchid-parser-parse-json-data-uses-preparse ()
  "orchid-parser-parse-json-data avoids double parsing."
  (let* ((data '(:type "assistant" :uuid "u3" :message (:content ((:type "text" :text "hello")))))
         (result (orchid-parser-parse-json-data data "{}")))
    (should result)
    (should (plist-get result :display))))

;;; Tool stub formatting tests

(ert-deftest orchid-parser-truncate-path-left-short ()
  "Path under max-len is returned unchanged."
  (should (string= "/short/path"
                   (orchid-parser--truncate-path-left "/short/path" 35))))

(ert-deftest orchid-parser-truncate-path-left-long ()
  "Path over max-len is left-truncated with ellipsis."
  (let* ((path "/home/user/.config/orchid/conversations/abc123")
         (result (orchid-parser--truncate-path-left path 35)))
    (should (= (length result) 35))
    (should (string-prefix-p "…" result))
    (should (string-suffix-p (substring path (- (length path) 34)) result))))

(ert-deftest orchid-parser-tool-call-stub-no-prefix ()
  "tool_call event for unknown tool uses [name] format."
  (let* ((data '(:type "tool_call"
                 :tool_call (:calls ((:id "c1" :name "example_tool" :input ())))))
         (result (orchid-parser--tool-call data))
         (display (plist-get result :display)))
    (should display)
    (should (string-match-p "\\[example_tool\\]" display))
    (should-not (string-match-p "tool call:" display))))

(ert-deftest orchid-parser-tool-call-stub-fs-read-short-path ()
  "fs_read with single :path shows [read] [path] signature."
  (let* ((data '(:type "tool_call"
                 :tool_call (:calls ((:id "c2" :name "fs_read"
                                      :input (:path "/short/path"))))))
         (result (orchid-parser--tool-call data))
         (display (plist-get result :display)))
    (should display)
    (should (string-match-p "\\[read\\] \\[/short/path\\]" display))))

(ert-deftest orchid-parser-tool-call-stub-fs-read-long-path ()
  "fs_read with long single :path shows left-truncated path in [read] stub."
  (let* ((long-path "/home/user/.config/orchid/conversations/abc123/somefile.el")
         (data `(:type "tool_call"
                 :tool_call (:calls ((:id "c3" :name "fs_read"
                                      :input (:path ,long-path))))))
         (result (orchid-parser--tool-call data))
         (display (plist-get result :display)))
    (should display)
    (should (string-match-p "\\[read\\] \\[…" display))
    (should-not (string-match-p (regexp-quote long-path) display))))

(ert-deftest orchid-parser-tool-call-stub-fs-read-batch ()
  "fs_read with :paths array shows [read] [N files] stub and lists paths in detail."
  (let* ((data '(:type "tool_call"
                 :tool_call (:calls ((:id "c4" :name "fs_read"
                                      :input (:paths ("./foo.el" "./bar.el" "./baz.el")))))))
         (result (orchid-parser--tool-call data))
         (display (plist-get result :display))
         (detail-fn (get-text-property 0 'orchid-collapsible-detail-fn display))
         (detail (funcall detail-fn)))
    (should display)
    (should (string-match-p "\\[read\\] \\[3 files\\]" display))
    (should (string-match-p "foo.el" detail))
    (should (string-match-p "bar.el" detail))
    (should (string-match-p "baz.el" detail))))

(ert-deftest orchid-parser-tool-call-stub-bash-cmd-preview ()
  "bash tool_call shows [bash] [cmd] signature."
  (let* ((data '(:type "tool_call"
                 :tool_call (:calls ((:id "c5" :name "bash"
                                      :input (:cmd "ls -la"))))))
         (result (orchid-parser--tool-call data))
         (display (plist-get result :display)))
    (should display)
    (should (string-match-p "\\[bash\\] \\[ls -la\\]" display))
    (should-not (string-match-p "tool call:" display))))

(ert-deftest orchid-parser-assistant-ignores-tool-use-items ()
  "tool_use content items in assistant events are silently ignored."
  (let* ((data '(:type "assistant"
                 :message (:content ((:type "tool_use" :name "some_tool" :id "t1" :input ())))))
         (result (orchid-parser--assistant data)))
    (should result)
    (should (string= "" (plist-get result :display)))))

(ert-deftest orchid-parser-tool-call-fs-edit-detail-contains-diff ()
  "fs_edit tool_call expanded detail contains diff output."
  (require 'parsers/orchid-parser-tool-use)
  (let* ((result (orchid-parser--tool-call
                  (list :type "tool_call"
                        :tool_call (list :calls
                                         (list (list :id "cid1"
                                                     :name "fs_edit"
                                                     :input (list :path "/foo/bar.el"
                                                                  :old_string "hello world"
                                                                  :new_string "hello emacs")))))))
         (collapsible (plist-get result :display))
         (detail-fn (get-text-property 0 'orchid-collapsible-detail-fn collapsible))
         (detail (funcall detail-fn)))
    (should (string-match-p "Path: /foo/bar.el" detail))
    (should (string-match-p "-hello world" detail))
    (should (string-match-p "+hello emacs" detail))))

(ert-deftest orchid-parser-tool-result-string-content-shown ()
  "tool_result with string content renders the content in detail."
  (require 'parsers/orchid-parser-tool-result)
  (let* ((result (orchid-parser--tool-result
                  (list :type "tool_result"
                        :tool_result (list :call_id "cid1"
                                          :content "applied successfully"))))
         (collapsible (plist-get result :display))
         (full-text (substring-no-properties collapsible)))
    (should (string-match-p "applied successfully" full-text))))

(ert-deftest orchid-parser-tool-result-fs-read-map-shows-paths ()
  "fs_read tool_result with map content: outer stub is lazy, inner stubs have correct paths."
  (require 'parsers/orchid-parser-tool-result)
  (let* ((json (concat "{\"type\":\"tool_result\",\"event_id\":\"e1\","
                       "\"timestamp\":\"2026-06-06T04:38:21.765384Z\","
                       "\"tool_result\":{\"call_id\":\"cid2\","
                       "\"content\":{\"./foo/bar.el\":\"line one\\nline two\","
                       "\"./baz/qux.el\":{\"error\":\"Is a directory\"}}}}"))
         (result (orchid-parser-parse-json json))
         (collapsible (plist-get result :display))
         (detail-fn (get-text-property 0 'orchid-collapsible-detail-fn collapsible))
         (detail (funcall detail-fn))
         (inner-text (substring-no-properties detail)))
    (should (string-match-p "foo/bar.el" inner-text))
    (should (string-match-p "baz/qux.el" inner-text))
    (should (string-match-p "line one" inner-text))
    (should (string-match-p "\\[error\\]" inner-text))
    (should (string-match-p "Is a directory" inner-text))))

(ert-deftest orchid-parser-tool-result-fs-read-map-parses-from-json ()
  "Full JSON parse of a tool_result event with map content succeeds."
  (require 'parsers/orchid-parser-tool-result)
  (let* ((json (concat "{\"type\":\"tool_result\",\"event_id\":\"e1\","
                       "\"timestamp\":\"2026-06-06T04:38:21.765384Z\","
                       "\"tool_result\":{\"call_id\":\"c1\","
                       "\"content\":{\"./README.md\":\"hello\","
                       "\"./missing\":{\"error\":\"not found\"}}}}"))
         (result (orchid-parser-parse-json json)))
    (should result)
    (should (string= "tool_result" (plist-get result :event-type)))
    (should (plist-get result :display))))

(provide 'orchid-parser-test)

;;; orchid-parser-test.el ends here
