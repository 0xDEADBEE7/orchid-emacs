# Chat Buffer Component

## Purpose

The **primary user interface** for Orchid. An IRC-style chat buffer where users type messages and see Claude's responses.

## UX Design

```
┌─────────────────────────────────────────┐
│  *Orchid Chat: my-project*              │
├─────────────────────────────────────────┤
│  [Read-only conversation area]          │
│                                         │
│  User: Help me debug this               │
│  Tool: Read tests.go [...] ← TAB toggles│
│  Claude: I found the issue...           │
│  User: Fix it please                    │
│  Tool: Edit tests.go [...] ← Collapsed  │
│                                         │
│  (scrolls as conversation grows)        │
│                                         │
├─────────────────────────────────────────┤
│  > Type message here... [RET to send]   │ ← Input prompt
└─────────────────────────────────────────┘
```

## Key Features

- **Read-only conversation area**: Top portion, cannot edit
- **Input prompt at bottom**: Like IRC/ERC, press RET to send, Shift-RET for newline
- **Input history**: M-p/M-n to cycle through previous messages (via `orchid-history.el`)
- **Live updates**: Log monitor inserts Claude's responses with deduplication
- **Collapsible sections**: TAB to toggle detailed content (tool outputs, etc.)
- **Per-buffer state**: Each chat buffer tracks its session ID
- **New session support**: Can create new sessions with optional persona

## Technical Implementation

### Major Mode

```elisp
(define-derived-mode orchid-chat-mode fundamental-mode "Orchid-Chat"
  "Major mode for Orchid chat buffers."
  (setq buffer-read-only t)  ; Conversation area read-only
  (setq-local orchid-chat--session-id nil)
  (setq-local orchid-chat--pending-new-session nil)
  (setq-local orchid-chat--input-marker nil)
  (setq-local orchid-chat--assistant-cursor nil))
```

### Buffer Structure

```
Point 1: (point-min)
   ↓
[Read-only conversation area]
   ↓
Point N: orchid-chat--input-marker (marks start of input area)
   ↓
> [Editable input area]
   ↓
Point M: (point-max)
```

### Key Variables

```elisp
(defvar-local orchid-chat--session-id nil
  "Session ID for this chat buffer.")

(defvar-local orchid-chat--pending-new-session nil
  "If non-nil, this is a pending new session with optional persona.
Set to the persona name or t for no persona.")

(defvar-local orchid-chat--input-marker nil
  "Marker for start of input area.")

(defvar-local orchid-chat--assistant-cursor nil
  "Marker for where assistant content gets inserted.")
```

## Public API

### Opening/Closing

```elisp
(orchid-chat-open session-id)
;; Opens chat buffer for SESSION-ID
;; Creates buffer, sets up input area, starts log monitoring
;; Returns the chat buffer

(orchid-chat-open-new &optional persona)
;; Opens chat buffer for a new session with optional PERSONA
;; Session will be created when first message is sent
;; Returns the chat buffer

(orchid-chat-close)
;; Closes current chat buffer
;; Stops log monitoring, kills buffer
```

### Inserting Messages

```elisp
(orchid-chat-insert-log-line buffer parsed-event)
;; Insert parsed log event into BUFFER's conversation area
;; PARSED-EVENT is plist from parser with :event-type and :display

(orchid-chat-insert-system-message message)
;; Insert system message (errors, notifications)
```

### Input Handling

```elisp
(orchid-chat-send-input)
;; Get text from input area, send via CLI, clear input
;; Bound to RET in input area
;; Handles both new and existing sessions

(orchid-chat-newline)
;; Insert newline in input area (Shift-RET)

(orchid-chat-handle-tab)
;; Handle TAB key: toggle collapsible section or insert tab
```

## Keybindings

```elisp
(defvar orchid-chat-mode-map
  (let ((map (make-sparse-keymap)))
    ;; In input area
    (define-key map (kbd "RET") 'orchid-chat-send-input)
    (define-key map (kbd "S-<return>") 'orchid-chat-newline)
    (define-key map (kbd "M-p") 'orchid-chat-previous-input)
    (define-key map (kbd "M-n") 'orchid-chat-next-input)

    ;; Collapsible sections
    (define-key map (kbd "TAB") 'orchid-chat-handle-tab)

    ;; Global in buffer
    (define-key map (kbd "C-c C-l") 'orchid-chat-show-session-browser)
    (define-key map (kbd "<backtab>") 'orchid-chat-show-session-browser)
    (define-key map (kbd "C-c C-q") 'orchid-chat-close)
    map))
```

## Implementation Details

### Creating Chat Buffer

```elisp
(defun orchid-chat-open (session-id)
  "Open chat buffer for SESSION-ID."
  (let* ((metadata (orchid-session--read-metadata session-id))
         (process-running (equal (plist-get metadata :status) "running"))
         (chat-buffer (orchid-chat--initialize-buffer session-id)))

    (with-current-buffer chat-buffer
      ;; Set up history cursor and [More] button
      (orchid-chat--setup-history-cursor)
      ;; Restore session history from JSONL log
      (let* ((result (orchid-chat--restore-session-history session-id chat-buffer))
             (count (plist-get result :count)))
        (orchid-chat--finalize-history-display count process-running)
        (when process-running
          (orchid-chat--setup-process-indicator session-id run-started-str)))
      ;; Start live monitoring
      (orchid-chat--start-log-monitoring session-id chat-buffer))

    (switch-to-buffer chat-buffer)
    chat-buffer))
```

### Sending Input

```elisp
(defun orchid-chat-send-input ()
  "Send input from input area to Claude."
  (interactive)
  (if (and orchid-chat--input-marker (< (point) orchid-chat--input-marker))
      (insert "\n")
    (orchid-chat--send-message)))

(defun orchid-chat--send-message ()
  "Send message from input area."
  (let ((message (orchid-chat--get-and-clear-input)))
    (when message
      (orchid-chat--display-user-message message)
      (orchid-chat--prepare-for-response)
      (if orchid-chat--pending-new-session
          (orchid-chat--send-to-new-session message)
        (orchid-chat--send-to-existing-session message)))))
```

For new sessions, `orchid-chat--handle-new-session-result` calls
`orchid-chat--activate-session` once the CLI returns the new session ID.
This starts log monitoring via `orchid-log-start-monitoring-with-retry`.

### Collapsible Section Handling

```elisp
(defun orchid-chat-handle-tab ()
  "Handle TAB key press.
If on a collapsible section, toggle it.
Otherwise, insert a tab character in the input area."
  (interactive)
  (unless (orchid-collapsible-toggle-at-point)
    ;; Not on a collapsible section
    (if (>= (point) orchid-chat--input-marker)
        (insert "\t")  ; In input area
      (message "Use TAB on collapsible sections to expand/collapse them"))))
```

### Inserting Updates

```elisp
(defun orchid-chat-insert-log-line (buffer parsed-event)
  "Insert parsed log event into BUFFER's conversation area."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (let ((inhibit-read-only t)
            (display-text (plist-get parsed-event :display))
            (at-end (= (point) (point-max))))

        (when display-text
          ;; Insert at assistant cursor
          (save-excursion
            (goto-char orchid-chat--assistant-cursor)
            (let ((start (point)))
              (insert display-text)
              (set-marker orchid-chat--assistant-cursor (point))
              ;; Register any collapsible sections
              (orchid-chat--register-collapsible-sections start (point)))))

        ;; Auto-scroll if at end
        (when at-end
          (goto-char (point-max)))))))

(defun orchid-chat--register-collapsible-sections (start end)
  "Register collapsible section IDs in buffer's invisibility spec.
Scans region from START to END for collapsible sections."
  (save-excursion
    (goto-char start)
    (let ((pos start)
          (seen-ids nil))
      (while (< pos end)
        (let ((section-id (get-text-property pos 'orchid-collapsible-id)))
          (when (and section-id (not (member section-id seen-ids)))
            ;; Found a new section ID, add to invisibility spec
            (unless (member section-id buffer-invisibility-spec)
              (add-to-invisibility-spec section-id))
            (push section-id seen-ids)))
        (setq pos (or (next-single-property-change pos 'orchid-collapsible-id nil end) end))))))
```

## Integration Points

- **[Log Monitor](log-monitor.md)**: Receives callbacks with parsed log updates
- **[CLI Wrapper](cli-wrapper.md)**: Sends messages via `orchid send`
- **[Session Manager](session-management.md)**: Maps session ID to buffer
- **[Session Browser](session-browser.md)**: Browser opens chat buffers
- **[Collapsible Sections](collapsible.md)**: TAB toggles collapsible content
- **Input History**: `orchid-history.el` provides M-p/M-n navigation
- **Processing Indicator**: `orchid-processing-indicator.el` for visual feedback

## Implementation Notes

### New Session Creation

When creating a new session via `orchid-chat-open-new`:
1. Chat buffer is created with pending state (`orchid-chat--pending-new-session` set to persona or `t`)
2. When first message is sent, `orchid-chat--send-to-new-session` calls the CLI
3. On success, `orchid-chat--activate-session` is called with the new session ID
4. `orchid-chat--activate-session` starts log monitoring via `orchid-log-start-monitoring-with-retry`
5. The CLI command used for deletion is `orchid delete --id ID`

### Collapsible Sections

Tool outputs and other long content use collapsible sections:
1. Parsers create sections via `orchid-collapsible-create`
2. Sections registered in buffer's invisibility spec as inserted
3. TAB key toggles section at point
4. State persists in text properties

### Event Deduplication

Log monitor tracks seen events (by UUID and tool_use_id) to prevent duplicates when Claude includes context from earlier responses.

## Next Steps

See:
- [Log Monitor](log-monitor.md) - How updates arrive with deduplication
- [CLI Wrapper](cli-wrapper.md) - How messages are sent
- [Collapsible Sections](collapsible.md) - UI component for long content
- [Session Browser](session-browser.md) - How sessions are selected
