;;; orchid-processing-indicator-test.el --- Tests for orchid-processing-indicator -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools, tests

;;; Code:

(require 'ert)
(require 'core/orchid-processing-indicator)

;;; orchid-processing-show / orchid-processing-stop lifecycle

(ert-deftest orchid-processing-test-show-sets-marker ()
  "orchid-processing-show sets the marker in the buffer."
  (let ((buf (generate-new-buffer "*orchid-proc-test*")))
    (unwind-protect
        (with-current-buffer buf
          (cl-letf (((symbol-function 'orchid-processing--attach-metadata-watch) #'ignore))
            (orchid-processing-show "test-session")
            (should orchid-processing--marker)
            (should (marker-buffer orchid-processing--marker))
            (orchid-processing-stop)))
      (kill-buffer buf))))

(ert-deftest orchid-processing-test-show-sets-timer ()
  "orchid-processing-show starts the update timer."
  (let ((buf (generate-new-buffer "*orchid-proc-timer-test*")))
    (unwind-protect
        (with-current-buffer buf
          (cl-letf (((symbol-function 'orchid-processing--attach-metadata-watch) #'ignore))
            (orchid-processing-show "test-session")
            (should orchid-processing--timer)
            (should (timerp orchid-processing--timer))
            (orchid-processing-stop)))
      (kill-buffer buf))))

(ert-deftest orchid-processing-test-stop-clears-state ()
  "orchid-processing-stop clears all buffer-local state."
  (let ((buf (generate-new-buffer "*orchid-proc-stop-test*")))
    (unwind-protect
        (with-current-buffer buf
          (cl-letf (((symbol-function 'orchid-processing--attach-metadata-watch) #'ignore))
            (orchid-processing-show "test-session")
            (orchid-processing-stop)
            (should-not orchid-processing--marker)
            (should-not orchid-processing--timer)
            (should-not orchid-processing--watch)
            (should-not orchid-processing--start-time)
            (should-not orchid-processing--session-id)))
      (kill-buffer buf))))

(ert-deftest orchid-processing-test-show-idempotent ()
  "orchid-processing-show is idempotent: second call is a no-op."
  (let ((buf (generate-new-buffer "*orchid-proc-idem-test*")))
    (unwind-protect
        (with-current-buffer buf
          (cl-letf (((symbol-function 'orchid-processing--attach-metadata-watch) #'ignore))
            (orchid-processing-show "sess-1")
            (let ((first-marker orchid-processing--marker))
              (orchid-processing-show "sess-2")
              (should (eq first-marker orchid-processing--marker)))
            (orchid-processing-stop)))
      (kill-buffer buf))))

;;; orchid-processing-finish

(ert-deftest orchid-processing-test-status-only-finishes-on-idle ()
  "A missing or malformed status must not finish processing."
  (let ((orchid-processing--marker t)
        (orchid-processing--finished nil)
        (orchid-processing--seen-running t)
        (orchid-processing--session-id "test-session"))
    (cl-letf (((symbol-function 'orchid-processing--read-status)
               (lambda (_) nil))
              ((symbol-function 'orchid-processing--refresh-chunk-count) #'ignore)
              ((symbol-function 'orchid-processing--read-state-value)
               (lambda (&rest _) nil))
              ((symbol-function 'orchid-session-notify-status-change) #'ignore))
      ;; The marker is deliberately not in a live buffer, so stub the guard.
      (cl-letf (((symbol-function 'marker-buffer) (lambda (_) t))
                ((symbol-function 'orchid-processing--update-display) #'ignore)
                ((symbol-function 'orchid-processing-stop) #'ignore))
        (orchid-processing--check-status)
        (should-not orchid-processing--finished)))))

(ert-deftest orchid-processing-test-finish-marks-finished ()
  "orchid-processing-finish sets finished flag and stops timer."
  (let ((buf (generate-new-buffer "*orchid-proc-finish-test*")))
    (unwind-protect
        (with-current-buffer buf
          (cl-letf (((symbol-function 'orchid-processing--attach-metadata-watch) #'ignore))
            (orchid-processing-show "test-session")
            (orchid-processing-finish)
            (should-not orchid-processing--timer)
            (should-not orchid-processing--watch)))
      (kill-buffer buf))))

;;; orchid-processing-update-status

(ert-deftest orchid-processing-test-update-status ()
  "orchid-processing-update-status stores the message."
  (let ((buf (generate-new-buffer "*orchid-proc-status-test*")))
    (unwind-protect
        (with-current-buffer buf
          (orchid-processing-update-status "Running Bash")
          (should (equal orchid-processing--status-message "Running Bash"))
          (orchid-processing-update-status nil)
          (should-not orchid-processing--status-message))
      (kill-buffer buf))))

(provide 'orchid-processing-indicator-test)

;;; orchid-processing-indicator-test.el ends here
