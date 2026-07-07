# CLI Wrapper Component

## Purpose

Execute `orchid` CLI commands from Emacs and parse results.

## Overview

All conversation management happens via the `orchid` CLI. This component wraps CLI execution to provide:
- Async and sync execution modes
- JSON parsing
- Error handling
- Process management

## Public API

### Message Sending

```elisp
(orchid-core-send message &optional conversation-id &rest args)
;; Send MESSAGE to CONVERSATION-ID (nil starts a new conversation)
;; ARGS: :await, :working-dir, :persona, :callback
;; Returns: process (async) or result plist (sync)
```

### Conversation Management

```elisp
(orchid-core-list &optional callback)
;; List all conversations
;; Returns/calls with: (:success t :data [...])

(orchid-core-set conversation-id &rest args)
;; Set properties on CONVERSATION-ID
;; ARGS: :label, :working-dir, :persona, :profile, :callback

(orchid-core-stop conversation-id &optional callback)
;; Stop the running tool loop for CONVERSATION-ID
```

### Configuration

```elisp
(orchid-core-config-current &optional callback)
;; Get the active config profile
```

### Utilities

```elisp
(orchid-core-cli-available-p)
;; Check if orchid CLI is in PATH

(orchid-core-get-version &optional callback)
;; Get orchid CLI version
```

## Data Structures

### Result Format (Success)

```elisp
(:success t
 :data <parsed-data>      ; From JSON if applicable
 :raw <raw-output>        ; Raw CLI output
 :exit-code 0
 :duration 1.23)
```

### Result Format (Error)

```elisp
(:success nil
 :error "Error message"
 :raw <raw-output>
 :exit-code 1
 :duration 0.45)
```

### Session Object

```elisp
;; Parsed from `orchid list`
(:id "abc123..."
 :label "my-project"
 :working-dir "/path/to/project"
 :persona "default")
```

## Implementation

### Configuration

```elisp
(defgroup orchid-core nil
  "Orchid CLI wrapper."
  :group 'orchid)

(defcustom orchid-core-cli-path "orchid"
  "Path to orchid CLI executable."
  :type 'string)

(defcustom orchid-core-default-timeout 300
  "Default timeout in seconds for CLI commands."
  :type 'number)
```

### Sync Execution

```elisp
(defun orchid-core--execute-internal-sync (args)
  "Execute ARGS synchronously, return result plist."
  (let* ((start-time (current-time))
         (output-buffer (generate-new-buffer " *orchid-output*"))
         (exit-code (apply #'call-process
                           orchid-core-cli-path
                           nil output-buffer nil args))
         (output (with-current-buffer output-buffer (buffer-string)))
         (duration (float-time (time-subtract (current-time) start-time))))
    (kill-buffer output-buffer)
    (orchid-core--make-result exit-code output duration)))
```

### Async Execution

```elisp
(defun orchid-core--execute-internal-async (args callback)
  "Execute ARGS asynchronously, call CALLBACK with result."
  (let ((start-time (current-time))
        (output-buffer (generate-new-buffer " *orchid-output*")))
    (make-process
     :name "orchid-cli"
     :buffer output-buffer
     :command (cons orchid-core-cli-path args)
     :sentinel
     (lambda (proc _event)
       (when (memq (process-status proc) '(exit signal))
         (let* ((exit-code (process-exit-status proc))
                (output (with-current-buffer output-buffer (buffer-string)))
                (duration (float-time (time-subtract (current-time) start-time))))
           (kill-buffer output-buffer)
           (when callback
             (funcall callback (orchid-core--make-result exit-code output duration)))))))))
```

## CLI Command Reference

### Send Message

```bash
orchid send [--id ID] [--await] [--persona NAME] [--working-dir PATH] "message"
```

### List Conversations

```bash
orchid list
```

### Set Conversation Properties

```bash
orchid set --id ID [--label LABEL] [--working-dir PATH] [--persona NAME] [--profile PROFILE]
```

### Stop Conversation

```bash
orchid stop --id ID
```

### Get Config

```bash
orchid config current
```

## Error Handling

```elisp
(defun orchid-core-cli-available-p ()
  "Check if orchid CLI is available."
  (executable-find orchid-core-cli-path))
```

CLI unavailability raises an error at call time — callers should check `orchid-core-cli-available-p` first.

## Integration Points

- **[Chat Buffer](chat-buffer.md)**: Calls `orchid-core-send` to send messages
- **[Session Manager](session-management.md)**: Calls `orchid-core-list`
- **[Session Browser](session-browser.md)**: Displays conversation list

## Testing

```elisp
;; Check CLI availability
(orchid-core-cli-available-p)  ; => t or nil

;; Test sync send (new conversation)
(orchid-core-send "Hello" nil :await t)

;; Test async send to existing conversation
(orchid-core-send "Hello" "abc123"
  :callback (lambda (result)
              (message "Result: %s" (plist-get result :success))))

;; List conversations
(orchid-core-list
 (lambda (result)
   (message "Conversations: %S" (plist-get result :data))))
```

## Next Steps

See:
- [Chat Buffer](chat-buffer.md) - Uses this to send messages
- [Session Manager](session-management.md) - Uses this for session ops
