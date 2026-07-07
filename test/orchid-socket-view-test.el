;;; orchid-socket-view-test.el --- Tests for orchid-socket-view -*- lexical-binding: t -*-

;;; Code:

(require 'ert)
(require 'core/orchid-socket-view)

(defgroup orchid-chat  nil "stub" :group 'applications)
(defgroup orchid-faces nil "stub" :group 'applications)

(defmacro with-sv-buffer (&rest body)
  "Run BODY in a temp buffer with socket-view state zeroed."
  `(with-temp-buffer
     (setq orchid-socket-view--process       nil
           orchid-socket-view--region-start  nil
           orchid-socket-view--region-end    nil
           orchid-socket-view--section-id    nil
           orchid-socket-view--collapsed     t
           orchid-socket-view--cmd           nil
           orchid-socket-view--lines         nil
           orchid-socket-view--partial       ""
           orchid-socket-view--prev-cr       nil
           orchid-socket-view--session-id    nil)
     ,@body))

;;; Region lifecycle

(ert-deftest orchid-sv-test-insert-puts-bar ()
  "Inserting the region creates a bar character in the buffer."
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (should (string-match-p "\u2588" (buffer-string)))))

(ert-deftest orchid-sv-test-active-p-after-insert ()
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (should (orchid-socket-view--active-p))))

(ert-deftest orchid-sv-test-active-p-before-insert ()
  (with-sv-buffer
   (should-not (orchid-socket-view--active-p))))

(ert-deftest orchid-sv-test-starts-collapsed ()
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (should orchid-socket-view--collapsed)))

;;; Redraw — collapsed hides body, expanded shows it

(ert-deftest orchid-sv-test-collapsed-hides-cmd ()
  "Box content is invisible when collapsed."
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (setq orchid-socket-view--cmd "git status"
         orchid-socket-view--collapsed t)
   (orchid-socket-view--redraw)
   (goto-char (point-min))
   (let ((found nil))
     (while (not (eobp))
       (when (and (get-text-property (point) 'invisible)
                  (string-match-p "git status"
                                  (buffer-substring (point) (min (+ (point) 20) (point-max)))))
         (setq found t))
       (forward-char 1))
     (should found))))

(ert-deftest orchid-sv-test-expanded-shows-cmd ()
  "Cmd line is rendered with '$ ' prefix inside the box when expanded."
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (setq orchid-socket-view--cmd "git status"
         orchid-socket-view--collapsed nil)
   (orchid-socket-view--redraw)
   (should (string-match-p "│ \\$ git status" (buffer-string)))))

(ert-deftest orchid-sv-test-expanded-shows-output ()
  "Output lines are rendered with two-space indent inside the box."
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (setq orchid-socket-view--cmd "ls"
         orchid-socket-view--lines '("file.txt")
         orchid-socket-view--collapsed nil)
   (orchid-socket-view--redraw)
   (should (string-match-p "│   file\\.txt" (buffer-string)))))

(ert-deftest orchid-sv-test-box-always-rendered ()
  "Box is rendered even with no cmd and no output."
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (setq orchid-socket-view--collapsed nil)
   (orchid-socket-view--redraw)
   (let ((s (buffer-string)))
     (should (string-match-p "┌shell" s))
     (should (string-match-p "┘" s)))))

(ert-deftest orchid-sv-test-box-fixed-height ()
  "Expanded box always contains exactly orchid-socket-view-lines output rows."
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (let ((orchid-socket-view-lines 3))
     ;; With only 1 real line, padding should bring total output rows to 3.
     (setq orchid-socket-view--cmd "ls"
           orchid-socket-view--lines '("only-line")
           orchid-socket-view--collapsed nil)
     (orchid-socket-view--redraw)
     (let ((count 0)
           (s (buffer-string)))
       (with-temp-buffer
         (insert s)
         (goto-char (point-min))
         (while (re-search-forward "^│   " nil t)
           (setq count (1+ count))))
       (should (= count 3))))))

(ert-deftest orchid-sv-test-box-row-width ()
  "Each box row occupies exactly orchid-socket-view--width display columns (excluding newline)."
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (setq orchid-socket-view--cmd "echo hello"
         orchid-socket-view--lines '("world")
         orchid-socket-view--collapsed nil)
   (orchid-socket-view--redraw)
   (goto-char (point-min))
   (while (not (eobp))
     (let* ((bol (point))
            (eol (line-end-position))
            (line (buffer-substring-no-properties bol eol)))
       ;; skip bar (█) and empty lines
       (unless (or (string-match-p "\u2588" line) (string-empty-p line))
         (should (= (string-width line) orchid-socket-view--width)))
       (forward-line 1)))))

(ert-deftest orchid-sv-test-tab-in-output-truncated ()
  "Lines containing tabs are truncated by display width, not char count."
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   ;; Tab at col 0 expands to 8 cols — a 200-char tab-padded line must still fit.
   (setq orchid-socket-view--cmd "cmd"
         orchid-socket-view--lines (list (concat "\t" (make-string 200 ?x)))
         orchid-socket-view--collapsed nil)
   (orchid-socket-view--redraw)
   (goto-char (point-min))
   (while (not (eobp))
     (let* ((bol (point))
            (eol (line-end-position))
            (line (buffer-substring-no-properties bol eol)))
       (unless (or (string-match-p "\u2588" line) (string-empty-p line))
         (should (= (string-width line) orchid-socket-view--width)))
       (forward-line 1)))))

(ert-deftest orchid-sv-test-cmd-truncated-at-newline ()
  "Multi-line cmd is truncated at the first newline."
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (setq orchid-socket-view--cmd "line1\nline2"
         orchid-socket-view--collapsed nil)
   (orchid-socket-view--redraw)
   (let ((s (buffer-string)))
     (should (string-match-p "\\$ line1" s))
     (should-not (string-match-p "line2" s)))))

(ert-deftest orchid-sv-test-long-output-truncated ()
  "Output lines longer than the box inner width are truncated, not wrapped."
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (setq orchid-socket-view--cmd "cmd"
         orchid-socket-view--lines (list (make-string 200 ?x))
         orchid-socket-view--collapsed nil)
   (orchid-socket-view--redraw)
   (goto-char (point-min))
   (while (not (eobp))
     (let* ((bol (point))
            (eol (line-end-position))
            (line (buffer-substring-no-properties bol eol)))
       (unless (or (string-match-p "\u2588" line) (string-empty-p line))
         (should (= (string-width line) orchid-socket-view--width)))
       (forward-line 1)))))

(ert-deftest orchid-sv-test-ring-capped ()
  "Ring is capped at orchid-socket-view-lines entries."
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (setq orchid-socket-view--cmd "cmd" orchid-socket-view--collapsed nil)
   (let ((orchid-socket-view-lines 3))
     (setq orchid-socket-view--lines '("a"))
     (dolist (l '("b" "c" "d" "e"))
       (orchid-socket-view--push l nil))
     (should (= 3 (length orchid-socket-view--lines))))))

;;; Toggle

(ert-deftest orchid-sv-test-toggle-expands ()
  "TAB on the bar expands the region."
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (goto-char orchid-socket-view--region-start)
   (should (orchid-socket-view-toggle-at-point))
   (should-not orchid-socket-view--collapsed)))

(ert-deftest orchid-sv-test-toggle-from-body ()
  "TAB anywhere inside the region also toggles."
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   ;; Expand first, then place point before the bar (inside body area)
   (setq orchid-socket-view--collapsed nil)
   (orchid-socket-view--redraw)
   (goto-char orchid-socket-view--region-start)
   (should (orchid-socket-view-toggle-at-point))
   (should orchid-socket-view--collapsed)))

(ert-deftest orchid-sv-test-toggle-outside-region-noop ()
  "TAB outside the region returns nil."
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (goto-char (point-max))
   (should-not (orchid-socket-view-toggle-at-point))))

;;; Clear

(ert-deftest orchid-sv-test-clear-resets-state ()
  "clear resets data but preserves collapsed state."
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (setq orchid-socket-view--cmd "ls"
         orchid-socket-view--lines '("x")
         orchid-socket-view--collapsed nil)
   (orchid-socket-view-clear)
   (should (null orchid-socket-view--cmd))
   (should (null orchid-socket-view--lines))
   ;; collapsed state is preserved — clear does not re-collapse
   (should-not orchid-socket-view--collapsed)))

;;; Stop

(ert-deftest orchid-sv-test-stop-removes-region ()
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (orchid-socket-view-stop)
   (should-not (orchid-socket-view--active-p))
   (should (= (point-min) (point-max)))))

;;; extract-cmd

(ert-deftest orchid-sv-test-extract-cmd-tool-start ()
  (should (equal "ls -la"
                 (orchid-socket-view--extract-cmd
                  "{\"type\":\"tool_start\",\"cmd\":\"ls -la\",\"call_id\":\"x\",\"name\":\"bash\",\"ts\":\"t\"}"))))

(ert-deftest orchid-sv-test-extract-cmd-tool-end-nil ()
  (should-not (orchid-socket-view--extract-cmd
               "{\"type\":\"tool_end\",\"call_id\":\"x\",\"exit_code\":0,\"ts\":\"t\"}")))

(ert-deftest orchid-sv-test-extract-cmd-non-json-nil ()
  (should-not (orchid-socket-view--extract-cmd "not json")))

;;; Filter

(ert-deftest orchid-sv-test-filter-tool-start-sets-cmd ()
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (let ((proc (start-process "dummy" (current-buffer) "true")))
     (unwind-protect
         (progn
           (orchid-socket-view--on-filter
            proc "{\"type\":\"tool_start\",\"cmd\":\"git status\",\"call_id\":\"x\",\"name\":\"bash\",\"ts\":\"t\"}\n")
           (should (equal "git status" orchid-socket-view--cmd))
           ;; cmd arriving does not auto-expand — user must press TAB
           (should orchid-socket-view--collapsed))
       (delete-process proc)))))

(ert-deftest orchid-sv-test-filter-tool-end-ignored ()
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (setq orchid-socket-view--cmd "ls" orchid-socket-view--collapsed nil)
   (let ((proc (start-process "dummy" (current-buffer) "true")))
     (unwind-protect
         (progn
           (orchid-socket-view--on-filter
            proc "{\"type\":\"tool_end\",\"call_id\":\"x\",\"exit_code\":0,\"ts\":\"t\"}\n")
           (should (equal "ls" orchid-socket-view--cmd)))
       (delete-process proc)))))

(ert-deftest orchid-sv-test-filter-bare-cr-replaces ()
  "bare \\r causes next line to replace the previous ring entry."
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (setq orchid-socket-view--cmd "spin" orchid-socket-view--collapsed nil)
   (let ((proc (start-process "dummy" (current-buffer) "true")))
     (unwind-protect
         (progn
           (orchid-socket-view--on-filter proc "frame1\rframe2\n")
           (should (equal (list "frame2") orchid-socket-view--lines)))
       (delete-process proc)))))

(ert-deftest orchid-sv-test-filter-crlf-replaces ()
  "\\r\\n also triggers replace semantics."
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (setq orchid-socket-view--cmd "spin" orchid-socket-view--collapsed nil)
   (let ((proc (start-process "dummy" (current-buffer) "true")))
     (unwind-protect
         (progn
           (orchid-socket-view--on-filter proc "frame1\r\nframe2\r\n")
           (should (equal (list "frame2") orchid-socket-view--lines)))
       (delete-process proc)))))

(ert-deftest orchid-sv-test-filter-plain-lf-accumulates ()
  "Plain \\n lines accumulate in the ring."
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (setq orchid-socket-view--cmd "cmd" orchid-socket-view--collapsed nil)
   (let ((proc (start-process "dummy" (current-buffer) "true")))
     (unwind-protect
         (progn
           (orchid-socket-view--on-filter proc "line1\nline2\n")
           (should (equal (list "line2" "line1") orchid-socket-view--lines)))
       (delete-process proc)))))

(ert-deftest orchid-sv-test-filter-partial-buffered ()
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (setq orchid-socket-view--cmd "cmd" orchid-socket-view--collapsed nil)
   (let ((proc (start-process "dummy" (current-buffer) "true")))
     (unwind-protect
         (progn
           (orchid-socket-view--on-filter proc "incom")
           (should (equal orchid-socket-view--partial "incom"))
           (should (null orchid-socket-view--lines)))
       (delete-process proc)))))

(ert-deftest orchid-sv-test-filter-assembles-chunks ()
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (setq orchid-socket-view--cmd "cmd" orchid-socket-view--collapsed nil)
   (let ((proc (start-process "dummy" (current-buffer) "true")))
     (unwind-protect
         (progn
           (orchid-socket-view--on-filter proc "hel")
           (orchid-socket-view--on-filter proc "lo\n")
           (should (equal (list "hello") orchid-socket-view--lines)))
       (delete-process proc)))))

(ert-deftest orchid-sv-test-cross-chunk-spinner-replace ()
  "A \\r at end of one chunk causes the first line of the next to replace."
  (with-sv-buffer
   (orchid-socket-view--insert (point))
   (setq orchid-socket-view--cmd "spin" orchid-socket-view--collapsed nil)
   (let ((proc (start-process "dummy" (current-buffer) "true")))
     (unwind-protect
         (progn
           (orchid-socket-view--on-filter proc "frame1\r")
           ;; prev-cr should now be set
           (should orchid-socket-view--prev-cr)
           ;; Next chunk: frame2 arrives as first line — should replace frame1
           (orchid-socket-view--on-filter proc "frame2\n")
           (should (equal (list "frame2") orchid-socket-view--lines)))
       (delete-process proc)))))

(provide 'orchid-socket-view-test)

;;; orchid-socket-view-test.el ends here
