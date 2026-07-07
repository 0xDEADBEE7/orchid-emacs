;;; orchid-log-restore-test.el --- Tests for log restore functionality -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools, tests

;;; Code:

(require 'ert)
(require 'orchid-log)
(require 'orchid-test-helpers)

;;; Helpers

(defun orchid-log-restore-test--make-jsonl (events)
  "Write EVENTS (list of JSON strings) to a temp file, return path."
  (let ((file (make-temp-file "orchid-test-" nil ".jsonl")))
    (with-temp-file file
      (dolist (event events)
        (insert event "\n")))
    file))

(defun orchid-log-restore-test--mock-find-file (file)
  "Return a mock for orchid-log--find-file that always returns FILE."
  (lambda (_session-id) file))

(defun orchid-log-restore-test--display-text (parsed-event)
  "Extract plain stub text from the :display of PARSED-EVENT."
  (substring-no-properties (plist-get parsed-event :display) 0 nil))

(defun orchid-log-restore-test--make-assistant-line (uuid text)
  "Return a JSON line for an assistant event with UUID and TEXT."
  (format "{\"type\":\"assistant\",\"uuid\":\"%s\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"%s\"}]}}"
          uuid text))

;;; Count and limit

(ert-deftest orchid-log-restore-test-full-forward ()
  "Forward scan (no max-events) returns all events."
  (let* ((lines (list
                 (orchid-log-restore-test--make-assistant-line "f1" "Hello")
                 (orchid-log-restore-test--make-assistant-line "f2" "World")))
         (file (orchid-log-restore-test--make-jsonl lines))
         (orchid-log-restore-max-events nil)
         (orchid-log-restore-max-size-mb nil)
         (events nil))
    (unwind-protect
        (cl-letf (((symbol-function 'orchid-log--find-file)
                   (orchid-log-restore-test--mock-find-file file)))
          (orchid-log-restore-session "test" (lambda (p) (push p events)))
          (should (= 2 (length events))))
      (delete-file file))))

(ert-deftest orchid-log-restore-test-full-backward ()
  "Backward scan respects max-events limit."
  (let* ((lines (list
                 (orchid-log-restore-test--make-assistant-line "g1" "A")
                 (orchid-log-restore-test--make-assistant-line "g2" "B")
                 (orchid-log-restore-test--make-assistant-line "g3" "C")))
         (file (orchid-log-restore-test--make-jsonl lines))
         (orchid-log-restore-max-events 2)
         (orchid-log-restore-max-size-mb nil)
         (events nil))
    (unwind-protect
        (cl-letf (((symbol-function 'orchid-log--find-file)
                   (orchid-log-restore-test--mock-find-file file)))
          (orchid-log-restore-session "test" (lambda (p) (push p events)))
          (should (= 2 (length events))))
      (delete-file file))))

;;; Chronological ordering

(ert-deftest orchid-log-restore-test-forward-scan-is-chronological ()
  "Forward scan delivers events oldest-first."
  (let* ((lines (list
                 (orchid-log-restore-test--make-assistant-line "c1" "First")
                 (orchid-log-restore-test--make-assistant-line "c2" "Second")
                 (orchid-log-restore-test--make-assistant-line "c3" "Third")))
         (file (orchid-log-restore-test--make-jsonl lines))
         (orchid-log-restore-max-events nil)
         (orchid-log-restore-max-size-mb nil)
         (events nil))
    (unwind-protect
        (cl-letf (((symbol-function 'orchid-log--find-file)
                   (orchid-log-restore-test--mock-find-file file)))
          (orchid-log-restore-session "test" (lambda (p) (push p events)))
          (let ((texts (mapcar #'orchid-log-restore-test--display-text (nreverse events))))
            (should (string-match-p "First"  (nth 0 texts)))
            (should (string-match-p "Second" (nth 1 texts)))
            (should (string-match-p "Third"  (nth 2 texts)))))
      (delete-file file))))

(ert-deftest orchid-log-restore-test-backward-scan-is-chronological ()
  "Backward scan delivers events oldest-first."
  (let* ((lines (list
                 (orchid-log-restore-test--make-assistant-line "b1" "First")
                 (orchid-log-restore-test--make-assistant-line "b2" "Second")
                 (orchid-log-restore-test--make-assistant-line "b3" "Third")))
         (file (orchid-log-restore-test--make-jsonl lines))
         (orchid-log-restore-max-events 3)
         (orchid-log-restore-max-size-mb nil)
         (events nil))
    (unwind-protect
        (cl-letf (((symbol-function 'orchid-log--find-file)
                   (orchid-log-restore-test--mock-find-file file)))
          (orchid-log-restore-session "test" (lambda (p) (push p events)))
          (let ((texts (mapcar #'orchid-log-restore-test--display-text (nreverse events))))
            (should (string-match-p "First"  (nth 0 texts)))
            (should (string-match-p "Second" (nth 1 texts)))
            (should (string-match-p "Third"  (nth 2 texts)))))
      (delete-file file))))

;;; Recency — backward scan must select the N most recent events

(ert-deftest orchid-log-restore-test-backward-scan-takes-most-recent ()
  "Backward scan with max-events N returns the last N events in the log, not the first N."
  (let* ((lines (list
                 (orchid-log-restore-test--make-assistant-line "r1" "OldFirst")
                 (orchid-log-restore-test--make-assistant-line "r2" "OldSecond")
                 (orchid-log-restore-test--make-assistant-line "r3" "RecentFirst")
                 (orchid-log-restore-test--make-assistant-line "r4" "RecentSecond")))
         (file (orchid-log-restore-test--make-jsonl lines))
         (orchid-log-restore-max-events 2)
         (orchid-log-restore-max-size-mb nil)
         (events nil))
    (unwind-protect
        (cl-letf (((symbol-function 'orchid-log--find-file)
                   (orchid-log-restore-test--mock-find-file file)))
          (orchid-log-restore-session "test" (lambda (p) (push p events)))
          (let ((texts (mapcar #'orchid-log-restore-test--display-text (nreverse events))))
            (should (= 2 (length texts)))
            (should (string-match-p "RecentFirst"  (nth 0 texts)))
            (should (string-match-p "RecentSecond" (nth 1 texts)))))
      (delete-file file))))

(ert-deftest orchid-log-restore-test-backward-scan-most-recent-chronological ()
  "Backward scan selects N most recent events AND delivers them oldest-first."
  (let* ((lines (list
                 (orchid-log-restore-test--make-assistant-line "d1" "Alpha")
                 (orchid-log-restore-test--make-assistant-line "d2" "Beta")
                 (orchid-log-restore-test--make-assistant-line "d3" "Gamma")
                 (orchid-log-restore-test--make-assistant-line "d4" "Delta")
                 (orchid-log-restore-test--make-assistant-line "d5" "Epsilon")))
         (file (orchid-log-restore-test--make-jsonl lines))
         (orchid-log-restore-max-events 3)
         (orchid-log-restore-max-size-mb nil)
         (events nil))
    (unwind-protect
        (cl-letf (((symbol-function 'orchid-log--find-file)
                   (orchid-log-restore-test--mock-find-file file)))
          (orchid-log-restore-session "test" (lambda (p) (push p events)))
          (let ((texts (mapcar #'orchid-log-restore-test--display-text (nreverse events))))
            ;; Selected: Gamma, Delta, Epsilon (3 most recent)
            (should (= 3 (length texts)))
            ;; Delivered oldest-first: Gamma, Delta, Epsilon
            (should (string-match-p "Gamma"   (nth 0 texts)))
            (should (string-match-p "Delta"   (nth 1 texts)))
            (should (string-match-p "Epsilon" (nth 2 texts)))))
      (delete-file file))))

(provide 'orchid-log-restore-test)

;;; orchid-log-restore-test.el ends here
