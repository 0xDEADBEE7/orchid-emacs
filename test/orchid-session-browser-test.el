;;; orchid-session-browser-test.el --- Tests for orchid-session-browser -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools, tests

;;; Code:

(require 'ert)
(require 'orchid-test-helpers)
(require 'session/orchid-session-browser)
(require 'browser/orchid-browser-marks)

(defmacro orchid-browser-test--with-config (json &rest body)
  "Run BODY with a temp config.json containing JSON bound as the config path."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "orchid-test-config-" t))
          (config-path (expand-file-name "config.json" dir))
          (orchid-session-browser-config-path config-path))
     (with-temp-file config-path (insert ,json))
     (unwind-protect
         (progn ,@body)
       (delete-directory dir t))))

;;; fetch-personas reads keys from config.json

(ert-deftest orchid-session-browser-test-fetch-personas-returns-keys ()
  "Personas are the keys of the personas object, not the array values."
  (orchid-browser-test--with-config
      "{\"personas\":{\"dev\":[\"base\",\"developer\"],\"ops\":[\"base\"]}}"
    (let ((personas (orchid-session-browser--fetch-personas)))
      (should (member "dev" personas))
      (should (member "ops" personas))
      (should (= 2 (length personas))))))

(ert-deftest orchid-session-browser-test-fetch-personas-single ()
  "Single persona group returns list with one entry."
  (orchid-browser-test--with-config
      "{\"personas\":{\"dev\":[\"base\",\"developer\",\"concise\"]}}"
    (let ((personas (orchid-session-browser--fetch-personas)))
      (should (equal '("dev") personas)))))

(ert-deftest orchid-session-browser-test-fetch-personas-no-personas-key ()
  "Config with no personas key returns nil."
  (orchid-browser-test--with-config
      "{\"active_profile\":\"cba-sonnet\",\"profiles\":{}}"
    (should-not (orchid-session-browser--fetch-personas))))

(ert-deftest orchid-session-browser-test-fetch-personas-missing-file ()
  "Non-existent config path returns nil."
  (let ((orchid-session-browser-config-path "/nonexistent/path/config.json"))
    (should-not (orchid-session-browser--fetch-personas))))

;;; orchid-session-browser-execute (marks)

(ert-deftest orchid-browser-marks-execute-kill-calls-stop ()
  "orchid-session-browser-execute kills marked sessions."
  (orchid-test-with-mocks
    (let ((buf (generate-new-buffer "*orchid-marks-test*")))
      (unwind-protect
          (with-current-buffer buf
            (setq-local orchid-session-browser--marked-sessions
                        (let ((h (make-hash-table :test 'equal)))
                          (puthash "sess-kill" 'kill h)
                          h))
            (cl-letf (((symbol-function 'orchid-session-browser-refresh) #'ignore)
                      ((symbol-function 'yes-or-no-p) (lambda (_prompt) t)))
              (orchid-session-browser-execute))
            (should (= 1 (length orchid-test-mock-cli-calls)))
            (let ((args (car orchid-test-mock-cli-calls)))
              (should (member "sess-kill" args))))
        (kill-buffer buf)))))

(ert-deftest orchid-browser-marks-execute-delete-calls-core ()
  "orchid-session-browser-execute deletes marked sessions via CLI."
  (orchid-test-with-mocks
    (let ((buf (generate-new-buffer "*orchid-marks-delete-test*")))
      (unwind-protect
          (with-current-buffer buf
            (setq-local orchid-session-browser--marked-sessions
                        (let ((h (make-hash-table :test 'equal)))
                          (puthash "sess-delete" 'delete h)
                          h))
            (cl-letf (((symbol-function 'orchid-session-browser-refresh) #'ignore)
                      ((symbol-function 'yes-or-no-p) (lambda (_prompt) t)))
              (orchid-session-browser-execute))
            (should (= 1 (length orchid-test-mock-cli-calls)))
            (let ((args (car orchid-test-mock-cli-calls)))
              (should (member "delete" args))
              (should (member "sess-delete" args))))
        (kill-buffer buf)))))

(ert-deftest orchid-browser-marks-execute-noop-when-empty ()
  "orchid-session-browser-execute is a no-op when no marks are set."
  (let ((buf (generate-new-buffer "*orchid-marks-empty-test*"))
        (refresh-called nil))
    (unwind-protect
        (with-current-buffer buf
          (setq-local orchid-session-browser--marked-sessions nil)
          (cl-letf (((symbol-function 'orchid-session-browser-refresh)
                     (lambda () (setq refresh-called t))))
            (orchid-session-browser-execute))
          (should-not refresh-called))
      (kill-buffer buf))))

(ert-deftest orchid-browser-marks-execute-preserves-failed-marks ()
  "orchid-session-browser-execute keeps marks for failed operations."
  (orchid-test-with-mocks
    (let ((buf (generate-new-buffer "*orchid-marks-fail-test*")))
      (unwind-protect
          (with-current-buffer buf
            (setq-local orchid-session-browser--marked-sessions
                        (let ((h (make-hash-table :test 'equal)))
                          (puthash "sess-delete" 'delete h)
                          h))
            ;; Mock CLI to return failure
            (cl-letf (((symbol-function 'orchid-session-browser-refresh) #'ignore)
                      ((symbol-function 'yes-or-no-p) (lambda (_prompt) t))
                      ((symbol-function 'orchid-core-delete)
                       (lambda (_id) (list :success nil :error "failed"))))
              (orchid-session-browser-execute))
            ;; Mark should be preserved since operation failed
            (should (= 1 (hash-table-count orchid-session-browser--marked-sessions))))
        (kill-buffer buf)))))

(ert-deftest orchid-browser-marks-execute-cancelled-when-not-confirmed ()
  "orchid-session-browser-execute does nothing when user cancels confirmation."
  (orchid-test-with-mocks
    (let ((buf (generate-new-buffer "*orchid-marks-cancel-test*"))
          (refresh-called nil))
      (unwind-protect
          (with-current-buffer buf
            (setq-local orchid-session-browser--marked-sessions
                        (let ((h (make-hash-table :test 'equal)))
                          (puthash "sess-delete" 'delete h)
                          h))
            (cl-letf (((symbol-function 'orchid-session-browser-refresh)
                       (lambda () (setq refresh-called t)))
                      ((symbol-function 'yes-or-no-p) (lambda (_prompt) nil)))
              (orchid-session-browser-execute))
            (should-not refresh-called)
            (should (= 1 (hash-table-count orchid-session-browser--marked-sessions))))
        (kill-buffer buf)))))

;;; orchid-session-browser-select (buffer cleanup)

(ert-deftest orchid-session-browser-select-kills-browser-buffer ()
  "Selecting a session destroys the browser buffer unconditionally."
  (orchid-test-with-mocks
    (let* ((chat-buf (generate-new-buffer "*orchid-chat-test*"))
           (browser-buf (get-buffer-create orchid-session-browser-buffer-name))
           (session `(:id "test-session" :chat-buffer ,chat-buf)))
      (unwind-protect
          (with-current-buffer browser-buf
            (cl-letf (((symbol-function 'orchid-session-browser--selected-session)
                       (lambda () session))
                      ((symbol-function 'switch-to-buffer) #'ignore))
              (orchid-session-browser-select))
            (should-not (get-buffer orchid-session-browser-buffer-name)))
        (when (buffer-live-p chat-buf) (kill-buffer chat-buf))
        (when (buffer-live-p browser-buf) (kill-buffer browser-buf))))))

(provide 'orchid-session-browser-test)

;;; orchid-session-browser-test.el ends here
