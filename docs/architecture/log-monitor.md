# Log Monitor Component

## Purpose

Monitor Claude Code log files and stream updates into chat buffers in real-time.

## Overview

```
Claude Code writes to log file
    ↓
auto-revert-tail-mode detects changes
    ↓
Log parser processes new lines
    ↓
Callback invoked with formatted output
    ↓
Chat buffer inserts update
```

## Key Features

- **File-based monitoring**: Uses `auto-revert-tail-mode` (built-in)
- **Extensible parsing**: Plugin system for custom log formatters
- **Per-session tracking**: Each session gets its own log buffer
- **Automatic cleanup**: Stops monitoring when chat closes

## Log File Location

Conversation logs are stored at a fixed path by convention:

```
~/.config/orchid/conversations/<session-id>/conversation.jsonl
```

The file is JSON Lines format — one JSON object per line.

## Public API

### Starting/Stopping

```elisp
(orchid-log-start-monitoring session-id callback)
;; Start monitoring log for SESSION-ID
;; CALLBACK called with each new log line: (callback log-line)
;; Returns log buffer

(orchid-log-stop-monitoring session-id)
;; Stop monitoring and kill log buffer

(orchid-log-monitoring-p session-id)
;; Check if currently monitoring SESSION-ID
```

### Buffer Access

```elisp
(orchid-log-get-buffer session-id)
;; Get log buffer for SESSION-ID (or nil)

(orchid-log-show session-id)
;; Display log buffer in window (for debugging)
```

### Parser Management

```elisp
(orchid-log-add-parser parser-fn)
;; Add custom parser function

(orchid-log-remove-parser parser-fn)
;; Remove parser function

(orchid-log-set-parsers parser-list)
;; Replace all parsers
```

## Data Structures

### Registry Entry

```elisp
;; Stored in orchid-log--registry
(:session-id "abc123..."
 :log-file "~/.config/orchid/conversations/abc123.../conversation.jsonl"
 :buffer #<buffer>
 :callback #'my-callback
 :last-position 12345)
```

## Implementation

### Core Logic

```elisp
(defvar orchid-log--registry nil
  "List of monitoring entries.")

(defun orchid-log-start-monitoring (session-id callback)
  "Start monitoring log file for SESSION-ID."
  (let* ((log-file (orchid-log--find-file session-id))
         (buffer (orchid-log--create-buffer session-id log-file)))

    ;; Enable auto-revert-tail-mode
    (with-current-buffer buffer
      (auto-revert-tail-mode 1)
      (setq-local auto-revert-interval 0.5)  ; Check every 0.5s

      ;; Hook to process new content
      (add-hook 'after-revert-hook
                (lambda ()
                  (orchid-log--process-new-content session-id))
                nil t))

    ;; Register
    (orchid-log--register session-id log-file buffer callback)
    buffer))
```

### Finding Log Files

```elisp
(defun orchid-log--find-file (session-id)
  "Return conversation log path for SESSION-ID, erroring if not found."
  (let ((path (expand-file-name
               (format "~/.config/orchid/conversations/%s/conversation.jsonl"
                       session-id))))
    (unless (file-exists-p path)
      (error "Cannot find log file for session %s" session-id))
    path))
```

### Processing Updates

```elisp
(defun orchid-log--process-new-content (session-id)
  "Process new content in log buffer for SESSION-ID."
  (let ((entry (orchid-log--get-entry session-id)))
    (when entry
      (let* ((buffer (plist-get entry :buffer))
             (last-pos (or (plist-get entry :last-position) 1))
             (callback (plist-get entry :callback)))

        (with-current-buffer buffer
          (goto-char last-pos)
          (while (not (eobp))
            (let ((line (buffer-substring-no-properties
                        (line-beginning-position)
                        (line-end-position))))

              ;; Parse and invoke callback
              (let ((parsed (orchid-log-parse-line line)))
                (when callback
                  (funcall callback parsed)))

              (forward-line 1)))

          ;; Update last position
          (orchid-log--set-last-position session-id (point)))))))
```

## Log Parsing System

### Parser Interface

```elisp
;; Parser function signature:
(defun my-parser (log-line)
  "Parse LOG-LINE and return formatted text or nil.
Return format:
  - String: Use this formatted text
  - nil: This parser doesn't handle this line, try next"
  ...)
```

### Parser Registry

```elisp
;; Register a handler for an event type
(orchid-parser-register "assistant" #'orchid-parser--assistant)
(orchid-parser-register "tool_result" #'orchid-parser--tool-result)

;; Dispatch a parsed JSON object to the registered handler
(orchid-parser-parse-json-data json-data raw-line)
;; Returns a plist with :display, :event-type keys, or nil
```

The registry is a hash table in `lisp/parsers/orchid-parser-registry.el`.
Each parser module registers itself at load time.

### Parser Modules

| Module | Event types handled |
|--------|---------------------|
| `parsers/orchid-parser-assistant.el` | `assistant`, `message` |
| `parsers/orchid-parser-user.el` | `user` |
| `parsers/orchid-parser-tool-use.el` | `tool_result` |
| `parsers/orchid-parser-utils.el` | Shared formatting helpers |

All parsers are loaded via `orchid-parsers.el`.

## Configuration

```elisp
(defgroup orchid-log nil
  "Log monitoring for Orchid."
  :group 'orchid)

(defcustom orchid-log-auto-revert-interval 0.5
  "How often to check for log updates (seconds)."
  :type 'number)

(defcustom orchid-log-show-raw-logs nil
  "If non-nil, show raw log buffers for debugging."
  :type 'boolean)

(defvar orchid-log-parsers
  '(orchid-parser-parse-json)
  "List of parser functions to try in order.
Currently a single entry that dispatches via the registry.")
```

## Integration Points

- **[Chat Buffer](chat-buffer.md)**: Registers callbacks to receive updates
- **[Session Manager](session-management.md)**: Tracks which sessions are monitored
- **[CLI Wrapper](cli-wrapper.md)**: May query for log file paths

## Performance Considerations

1. **Tail mode is efficient**: Only processes new content
2. **Parsing overhead**: Keep parsers simple, avoid heavy regex
3. **Buffer management**: Kill log buffers when chat closes

## Debugging

```elisp
;; Show raw log buffer
(orchid-log-show "session-id")

;; Check monitoring status
(orchid-log-monitoring-p "session-id")

;; List all monitored sessions
(orchid-log-list-monitored)
```

## Next Steps

See:
- [Chat Buffer](chat-buffer.md) - How updates are displayed
- Parser implementations: `lisp/parsers/orchid-parser-assistant.el`,
  `lisp/parsers/orchid-parser-tool-use.el`, `lisp/parsers/orchid-parser-user.el`
