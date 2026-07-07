;;; orchid-log-monitor.el --- Retry logic for log file monitoring -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Chris Abram
;; Keywords: tools

;;; Commentary:

;; Retry wrapper around orchid-log-start-monitoring for sessions where the
;; log file may not yet exist (e.g. new session creation in flight).

;;; Code:

(declare-function orchid-log-monitoring-p "orchid-log" (session-id))
(declare-function orchid-log-start-monitoring "orchid-log" (session-id callback))
(declare-function orchid-log--conversation-file "orchid-log" (session-id))
(declare-function orchid-log "orchid-logging" (&rest args))

(defun orchid-log-start-monitoring-with-retry (session-id callback max-retries retry-interval)
  "Start monitoring log file for SESSION-ID with retry logic."
  (when (orchid-log-monitoring-p session-id)
    (error "Already monitoring session %s" session-id))
  (orchid-log--try-start-monitoring session-id callback 0 max-retries retry-interval))

(defun orchid-log--try-start-monitoring (session-id callback retry-count max-retries retry-interval)
  "Try to start monitoring, retrying up to MAX-RETRIES times."
  (orchid-log "[monitor] try %d/%d session=%s file-exists=%s"
              retry-count max-retries session-id
              (file-exists-p (orchid-log--conversation-file session-id)))
  (condition-case err
      (orchid-log-start-monitoring session-id callback)
    (error
     (orchid-log "[monitor] error on try %d: %s" retry-count (error-message-string err))
     (if (< retry-count max-retries)
         (progn
           (message "Log file not found for %s, retrying (%d/%d)..."
                    session-id (1+ retry-count) max-retries)
           (run-with-timer
            retry-interval nil
            (lambda ()
              (orchid-log--try-start-monitoring
               session-id callback (1+ retry-count) max-retries retry-interval)))
           nil)
       (orchid-log "[monitor] GAVE UP after %d retries for session %s" max-retries session-id)
       (error "Failed to start monitoring for %s after %d retries: %s"
              session-id max-retries (error-message-string err))))))

(provide 'log/orchid-log-monitor)

;;; orchid-log-monitor.el ends here
