;;; orchid-collapsible-test.el --- Tests for orchid-collapsible -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools, tests

;;; Code:

(require 'ert)
(require 'core/orchid-collapsible)

(ert-deftest orchid-collapsible-create-returns-string ()
  "orchid-collapsible-create returns a string."
  (let ((result (orchid-collapsible-create "stub" "detail")))
    (should (stringp result))))

(ert-deftest orchid-collapsible-create-has-text-properties ()
  "orchid-collapsible-create marks stub with expected text properties."
  (let* ((result (orchid-collapsible-create "stub text" "detail text"))
         (id (get-text-property 0 'orchid-collapsible-id result)))
    (should (get-text-property 0 'orchid-collapsible result))
    (should (symbolp id))
    (should (eq 'stub (get-text-property 0 'orchid-collapsible-region result)))))

(ert-deftest orchid-collapsible-create-initially-collapsed ()
  "When initially-collapsed is t, stub state is 'collapsed."
  (let* ((result (orchid-collapsible-create "stub" "detail" t))
         (state (get-text-property 0 'orchid-collapsible-state result)))
    (should (eq state 'collapsed))))

(ert-deftest orchid-collapsible-create-initially-expanded ()
  "When initially-collapsed is nil, stub state is 'expanded."
  (let* ((result (orchid-collapsible-create "stub" "detail" nil))
         (state (get-text-property 0 'orchid-collapsible-state result)))
    (should (eq state 'expanded))))

(ert-deftest orchid-collapsible-toggle-at-point-collapses ()
  "Toggle at point on an expanded collapsible stub makes detail invisible."
  (with-temp-buffer
    ;; Initialize invisibility spec as a list (as orchid-chat--setup-buffer does)
    (setq buffer-invisibility-spec '())
    (add-to-invisibility-spec t)
    (let* ((section (orchid-collapsible-create "stub" "detail text" nil)))
      (insert section)
      (goto-char (point-min))
      ;; Section starts expanded; toggle should collapse it
      (should (orchid-collapsible-toggle-at-point))
      ;; After toggle stub state should be 'collapsed
      (goto-char (point-min))
      (should (eq 'collapsed (get-text-property (point) 'orchid-collapsible-state))))))

(ert-deftest orchid-collapsible-toggle-at-point-returns-nil-outside ()
  "Toggle at point outside a collapsible section returns nil."
  (with-temp-buffer
    (insert "plain text")
    (goto-char (point-min))
    (should-not (orchid-collapsible-toggle-at-point))))

(ert-deftest orchid-collapsible-create-lazy-calls-detail-fn-once ()
  "Lazy detail-fn is called exactly once on first expand."
  (with-temp-buffer
    (setq buffer-invisibility-spec '())
    (add-to-invisibility-spec t)
    (let* ((call-count 0)
           (detail-fn (lambda ()
                        (setq call-count (1+ call-count))
                        "lazy detail"))
           (section (orchid-collapsible-create-lazy "stub" detail-fn t)))
      (insert section)
      ;; First toggle: section was collapsed → should expand and materialize
      (goto-char (point-min))
      (orchid-collapsible-toggle-at-point)
      (should (= call-count 1))
      ;; Second toggle: collapse → should NOT call detail-fn again
      (goto-char (point-min))
      (orchid-collapsible-toggle-at-point)
      (should (= call-count 1)))))

(ert-deftest orchid-collapsible-unique-ids ()
  "Each created section gets a unique ID."
  (let* ((s1 (orchid-collapsible-create "stub1" "detail1"))
         (s2 (orchid-collapsible-create "stub2" "detail2"))
         (id1 (get-text-property 0 'orchid-collapsible-id s1))
         (id2 (get-text-property 0 'orchid-collapsible-id s2)))
    (should (not (eq id1 id2)))))

(provide 'orchid-collapsible-test)

;;; orchid-collapsible-test.el ends here
