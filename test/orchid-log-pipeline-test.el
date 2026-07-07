;;; orchid-log-pipeline-test.el --- Tests for orchid-log pipeline and deduplication -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools, tests

;;; Code:

(require 'ert)
(require 'orchid-log)
(require 'log/orchid-log-registry)

;;; Event deduplication (mark-event-seen / event-seen-p)

(ert-deftest orchid-log-test-event-seen-p-returns-nil-before-mark ()
  "event-seen-p returns nil for an event ID not yet marked."
  (let ((orchid-log--registry nil)
        (buf (generate-new-buffer " *test-log-dup*")))
    (unwind-protect
        (progn
          (orchid-log--register "sess-dup" "/tmp/dup.log" buf nil)
          (should-not (orchid-log--event-seen-p "sess-dup" "uuid-001")))
      (kill-buffer buf)
      (setq orchid-log--registry nil))))

(ert-deftest orchid-log-test-event-seen-p-returns-t-after-mark ()
  "event-seen-p returns t after mark-event-seen is called."
  (let ((orchid-log--registry nil)
        (buf (generate-new-buffer " *test-log-dup2*")))
    (unwind-protect
        (progn
          (orchid-log--register "sess-dup2" "/tmp/dup2.log" buf nil)
          (orchid-log--mark-event-seen "sess-dup2" "uuid-002")
          (should (orchid-log--event-seen-p "sess-dup2" "uuid-002")))
      (kill-buffer buf)
      (setq orchid-log--registry nil))))

(ert-deftest orchid-log-test-event-seen-p-nil-id-always-false ()
  "event-seen-p returns nil when event-id is nil (non-deduplicated events)."
  (let ((orchid-log--registry nil)
        (buf (generate-new-buffer " *test-log-nil*")))
    (unwind-protect
        (progn
          (orchid-log--register "sess-nil" "/tmp/nil.log" buf nil)
          (should-not (orchid-log--event-seen-p "sess-nil" nil)))
      (kill-buffer buf)
      (setq orchid-log--registry nil))))

(ert-deftest orchid-log-test-mark-event-seen-noop-for-nil-id ()
  "mark-event-seen is a no-op when event-id is nil."
  (let ((orchid-log--registry nil)
        (buf (generate-new-buffer " *test-log-mark-nil*")))
    (unwind-protect
        (progn
          (orchid-log--register "sess-mark-nil" "/tmp/mark-nil.log" buf nil)
          ;; Should not signal an error
          (orchid-log--mark-event-seen "sess-mark-nil" nil)
          (should-not (orchid-log--event-seen-p "sess-mark-nil" nil)))
      (kill-buffer buf)
      (setq orchid-log--registry nil))))

;;; Queue-timestamp filtering

(ert-deftest orchid-log-test-set-last-queue-timestamp ()
  "set-last-queue-timestamp stores the timestamp in the registry entry."
  (let ((orchid-log--registry nil)
        (buf (generate-new-buffer " *test-log-ts*")))
    (unwind-protect
        (progn
          (orchid-log--register "sess-ts" "/tmp/ts.log" buf nil)
          (orchid-log--set-last-queue-timestamp "sess-ts" "2024-01-01T12:00:00Z")
          (let ((entry (orchid-log--get-entry "sess-ts")))
            (should (equal "2024-01-01T12:00:00Z"
                           (plist-get entry :last-queue-timestamp)))))
      (kill-buffer buf)
      (setq orchid-log--registry nil))))

;;; process-new-content deduplication

(ert-deftest orchid-log-test-process-new-content-deduplicates ()
  "orchid-log--process-new-content skips duplicate event IDs."
  (let* ((orchid-log--registry nil)
         (orchid-log--event-deduplication t)
         (called-count 0)
         ;; Two lines with the same UUID
         (line1 "{\"type\":\"assistant\",\"uuid\":\"dup-uuid\",\"timestamp\":\"2024-01-01T00:00:01Z\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"hello\"}]}}")
         (buf (generate-new-buffer " *test-dedup*")))
    (unwind-protect
        (with-current-buffer buf
          (insert line1 "\n")
          (insert line1 "\n")
          (orchid-log--register "sess-dedup" "/tmp/dedup.log" buf
                                (lambda (_event) (setq called-count (1+ called-count))))
          (orchid-log--set-last-position "sess-dedup" 1)
          (orchid-log--process-new-content "sess-dedup")
          ;; Second occurrence should be deduplicated — only 1 callback
          (should (= 1 called-count)))
      (kill-buffer buf)
      (setq orchid-log--registry nil))))

(ert-deftest orchid-log-test-process-new-content-skips-old-turn-events ()
  "orchid-log--process-new-content skips events older than the queue timestamp."
  (let* ((orchid-log--registry nil)
         (orchid-log--event-deduplication nil)
         (called-count 0)
         ;; An event timestamped before the queue dequeue timestamp
         (old-line "{\"type\":\"assistant\",\"uuid\":\"old-uuid\",\"timestamp\":\"2024-01-01T00:00:01Z\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"old\"}]}}")
         (buf (generate-new-buffer " *test-oldturn*")))
    (unwind-protect
        (with-current-buffer buf
          (insert old-line "\n")
          (orchid-log--register "sess-old" "/tmp/old.log" buf
                                (lambda (_event) (setq called-count (1+ called-count))))
          (orchid-log--set-last-position "sess-old" 1)
          ;; Set queue timestamp *after* the event's timestamp
          (orchid-log--set-last-queue-timestamp "sess-old" "2024-01-01T01:00:00Z")
          (orchid-log--process-new-content "sess-old")
          ;; Event should be skipped (timestamp < queue timestamp)
          (should (= 0 called-count)))
      (kill-buffer buf)
      (setq orchid-log--registry nil))))

;;; set-last-position (regression: plist-put mutates in-place)

(ert-deftest orchid-log-test-set-last-position-updates-entry ()
  "set-last-position updates the entry's :last-position in the registry."
  (let ((orchid-log--registry nil)
        (buf (generate-new-buffer " *test-pos*")))
    (unwind-protect
        (progn
          (orchid-log--register "sess-pos" "/tmp/pos.log" buf nil)
          (orchid-log--set-last-position "sess-pos" 42)
          (let ((entry (orchid-log--get-entry "sess-pos")))
            (should (= 42 (plist-get entry :last-position)))))
      (kill-buffer buf)
      (setq orchid-log--registry nil))))

(provide 'orchid-log-pipeline-test)

;;; orchid-log-pipeline-test.el ends here
