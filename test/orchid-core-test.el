;;; orchid-core-test.el --- Unit tests for orchid-core -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools, tests

;;; Code:

(require 'ert)
(require 'core/orchid-core)
(require 'orchid-test-helpers)

;;; Helpers

(defmacro orchid-core-test--with-mock-execute (exit-code output &rest body)
  "Run BODY with `orchid-core--execute-internal-sync' mocked to return EXIT-CODE and OUTPUT.
Captures the last args list in `captured-args'."
  (declare (indent 2))
  `(let (captured-args)
     (cl-letf (((symbol-function 'orchid-core-cli-available-p) (lambda () t))
               ((symbol-function 'orchid-core--execute-internal-sync)
                (lambda (args)
                  (setq captured-args args)
                  (orchid-core--make-result ,exit-code ,output 0.0))))
       ,@body)))

;;; CLI availability

(ert-deftest orchid-core-test-cli-available-p ()
  "Test CLI availability check."
  (let ((orchid-core-cli-path "nonexistent-cli"))
    (should-not (orchid-core-cli-available-p)))
  (let ((orchid-core-cli-path "ls"))
    (should (orchid-core-cli-available-p))))

;;; JSON parsing

(ert-deftest orchid-core-test-parse-json-object ()
  (let ((result (orchid-core--parse-json "{\"id\":\"abc\",\"status\":\"idle\"}")))
    (should (equal "abc" (plist-get result :id)))
    (should (equal "idle" (plist-get result :status)))))

(ert-deftest orchid-core-test-parse-json-valid ()
  "Test parsing valid JSON output."
  (let ((result (orchid-core--parse-json "{\"key\":\"value\",\"number\":42}")))
    (should (plistp result))
    (should (equal "value" (plist-get result :key)))
    (should (equal 42 (plist-get result :number)))))

(ert-deftest orchid-core-test-parse-json-invalid ()
  (should (equal "not json" (orchid-core--parse-json "not json"))))

(ert-deftest orchid-core-test-parse-json-array ()
  "Test parsing JSON array."
  (let ((result (orchid-core--parse-json "[{\"id\":1},{\"id\":2}]")))
    (should (listp result))
    (should (= 2 (length result)))))

;;; Error extraction

(ert-deftest orchid-core-test-extract-error-from-json ()
  (should (equal "persona not found: default"
                 (orchid-core--extract-error "{\"error\":\"persona not found: default\"}"))))

(ert-deftest orchid-core-test-extract-error-from-plain ()
  (should (equal "some error" (orchid-core--extract-error "some error"))))

;;; make-result

(ert-deftest orchid-core-test-make-result-success ()
  (let ((r (orchid-core--make-result 0 "{\"id\":\"x\"}" 0.1)))
    (should (plist-get r :success))
    (should (equal "x" (plist-get (plist-get r :data) :id)))
    (should (= 0 (plist-get r :exit-code)))))

(ert-deftest orchid-core-test-make-result-failure ()
  (let ((r (orchid-core--make-result 1 "{\"error\":\"bad\"}" 0.1)))
    (should-not (plist-get r :success))
    (should (equal "bad" (plist-get r :error)))))

;;; Synchronous execution

(ert-deftest orchid-core-test-execute-sync-success ()
  "Test successful synchronous execution."
  (orchid-test-with-mocks
   (let ((result (orchid-core--execute-internal-sync '("test" "args"))))
     (should (plist-get result :success))
     (should (= 0 (plist-get result :exit-code)))
     (should (numberp (plist-get result :duration))))))

;;; Version

(ert-deftest orchid-core-test-get-version-sync ()
  "Test getting CLI version synchronously."
  (orchid-test-with-mocks
   (let ((result (orchid-core-get-version)))
     (should (plist-get result :success)))))

(ert-deftest orchid-core-test-get-version-async ()
  "Test getting CLI version asynchronously."
  (orchid-test-with-mocks
   (let ((callback-called nil)
         (callback-result nil))
     (orchid-core-get-version
      (lambda (result)
        (setq callback-called t)
        (setq callback-result result)))
     (should callback-called)
     (should (plist-get callback-result :success)))))

;;; Sessions

(ert-deftest orchid-core-test-sessions-list ()
  "Test listing sessions."
  (orchid-test-with-mocks
   (let ((result (orchid-core-list)))
     (should (plist-get result :success))
     (should (member "list" (car orchid-test-mock-cli-calls))))))

;;; send argument ordering

(ert-deftest orchid-core-test-send-message-last ()
  "Message must be the last argument so orchid send [options] \"message\" is correct."
  (orchid-core-test--with-mock-execute 0 "{\"id\":\"new\"}"
    (orchid-core-send "hello" nil)
    (should (equal (car (last captured-args)) "hello"))
    (should (equal (car captured-args) "send"))))

(ert-deftest orchid-core-test-send-with-id-message-last ()
  "With --id flag, message must still be last."
  (orchid-core-test--with-mock-execute 0 "{\"id\":\"x\"}"
    (orchid-core-send "hello" "session-id-123")
    (should (equal (car (last captured-args)) "hello"))
    (let ((id-pos (cl-position "--id" captured-args :test #'equal))
          (msg-pos (cl-position "hello" captured-args :test #'equal)))
      (should (< id-pos msg-pos)))))



(ert-deftest orchid-core-test-send-result-success ()
  (orchid-core-test--with-mock-execute 0 "{\"id\":\"new-id\",\"status\":\"idle\"}"
    (let ((r (orchid-core-send "test" nil)))
      (should (plist-get r :success))
      (should (equal "new-id" (plist-get (plist-get r :data) :id))))))

(ert-deftest orchid-core-test-send-result-failure ()
  (orchid-core-test--with-mock-execute 1 "{\"error\":\"persona not found: default\"}"
    (let ((r (orchid-core-send "test" nil :persona "default")))
      (should-not (plist-get r :success))
      (should (equal "persona not found: default" (plist-get r :error))))))


;;; Environment variable propagation to child processes

(ert-deftest orchid-core-test-setenv-reaches-child ()
  "Variables set with setenv must be visible to child processes spawned by Emacs."
  (let* ((key "ORCHID_TEST_ENV_VAR")
         (val "test-value-12345")
         (_ (setenv key val))
         (buf (generate-new-buffer " *env-test*"))
         (_ (call-process "env" nil buf nil))
         (output (with-current-buffer buf (buffer-string))))
    (kill-buffer buf)
    (setenv key nil)
    (should (string-match-p (regexp-quote (format "%s=%s" key val)) output))))

(provide 'orchid-core-test)

;;; orchid-core-test.el ends here
