# Session Management Component

## Purpose

Track Claude Code sessions within Emacs. Maintains mapping between session IDs, chat buffers, and log monitors.

## Overview

This component is Emacs' local view of sessions. The `orchid` CLI is the source of truth; this component caches and tracks sessions for UI purposes.

## Responsibilities

1. **Cache session list** from CLI
2. **Map session ID → chat buffer**
3. **Map session ID → log buffer**
4. **Track monitoring state**
5. **Track running state** and fire `orchid-session-status-change-functions`
6. **Provide session lookup** by ID or label

## Public API

### Session Retrieval

```elisp
(orchid-session-list)
;; Get cached session list
;; Returns: list of session plists

(orchid-session-refresh &optional callback)
;; Refresh from CLI, update cache
;; Synchronous if no CALLBACK; async otherwise

(orchid-session-get session-id-or-label)
;; Get session by ID or label
;; Returns: session plist or nil
```

### Session State

```elisp
(orchid-session-open session-id)
;; Open chat via orchid-chat-open + start monitoring
;; Returns: chat buffer

(orchid-session-close session-id)
;; Kill chat buffer + stop monitoring

(orchid-session-register session)
;; Add or replace SESSION in registry without a full refresh
;; Used when a new session is created locally

(orchid-session-get-chat-buffer session-id)
;; Get associated chat buffer

(orchid-session-get-log-buffer session-id)
;; Get associated log buffer

(orchid-session-monitoring-p session-id)
;; Check if monitoring active

(orchid-session-running-p session-id)
;; Return cached :running flag for SESSION-ID
```

### Status Change Hook

```elisp
(orchid-session-notify-status-change session-id running)
;; Update :running in registry and fire hook

(defvar orchid-session-status-change-functions nil)
;; Abnormal hook: each fn receives (SESSION-ID RUNNING)
```

### Current Session (Buffer-Local)

```elisp
(orchid-session-current)
;; Get current session ID for this buffer

(orchid-session-set-current session-id)
;; Set current session for this buffer
```

## Data Structures

### Session Object

```elisp
;; Core data (from CLI)
(:id "abc123..."
 :label "my-project"
 :working-dir "/path/to/project"
 :persona "default"
 :updated_at "2024-01-01T00:00:00Z"

 ;; Emacs-local state (preserved across registry refreshes)
 :chat-buffer #<buffer>      ; If open
 :log-buffer #<buffer>       ; If monitoring
 :monitoring-p t             ; Monitoring active?
 :running t)                 ; Process running?
```

### Registry Structure

```elisp
(defvar orchid-session--registry nil
  "Alist: (session-id . session-plist)")
```

Label lookup is done by `cl-find-if` over the registry; there is no separate
by-label index.

## Implementation

### Registry Management

```elisp
(defun orchid-session-refresh (&optional callback)
  "Refresh session list from CLI. Async if CALLBACK provided."
  (if callback
      (orchid-core-list
       (lambda (result)
         (when (plist-get result :success)
           (orchid-session--update-registry (plist-get result :data))
           (funcall callback ...))))
    ;; Synchronous path
    (let ((result (orchid-core-list)))
      (when (plist-get result :success)
        (orchid-session--update-registry (plist-get result :data))))))

(defun orchid-session--update-registry (sessions)
  "Rebuild registry from SESSIONS, preserving Emacs-local state."
  (let ((new-registry nil))
    (dolist (session sessions)
      (orchid-session--preserve-state session)   ; copy :chat-buffer etc.
      (push (cons (plist-get session :id) session) new-registry))
    (setq orchid-session--registry new-registry)))
```

### Opening Sessions

`orchid-session-open` delegates to `orchid-chat-open` (required lazily to
avoid a circular dependency at load time):

```elisp
(defun orchid-session-open (session-id)
  "Open chat buffer and start monitoring for SESSION-ID."
  ;; Cleans up dead buffers, stops leftover monitoring,
  ;; then calls:
  (require 'orchid-chat)
  (let ((chat-buffer (orchid-chat-open session-id)))
    (plist-put session :chat-buffer chat-buffer)
    (plist-put session :log-buffer (orchid-log-get-buffer session-id))
    (plist-put session :monitoring-p t)
    chat-buffer))
```

### Cleanup

```elisp
;; Dead-buffer cleanup runs every 5 minutes via idle timer
(run-with-idle-timer 300 t #'orchid-session-cleanup)
```

## Integration Points

- **[Chat Buffer](chat-buffer.md)**: Opens via `orchid-session-open` → `orchid-chat-open`
- **[Log Monitor](log-monitor.md)**: Monitoring state tracked here; `orchid-log-get-buffer` used after `orchid-chat-open`
- **[Session Browser](session-browser.md)**: Displays sessions from registry; subscribes to `orchid-session-status-change-functions`

## Next Steps

See:
- [Session Browser](session-browser.md) - UI for switching sessions
- [Chat Buffer](chat-buffer.md) - Opens via `orchid-session-open`
