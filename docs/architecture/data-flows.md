# Data Flows

## Overview

Key interaction flows through the Orchid system with current architecture (post-Refactor 00).

## 1. Initial Startup (Existing Session)

```
User: M-x orchid
  ↓
orchid-session-browser-show
  ↓
Session browser displays with search
  ├─ New session options (with personas)
  └─ Existing sessions (filtered by search)
  ↓
orchid-session-refresh (fetch from CLI)
  ↓
orchid-session-browser--render
  ↓
User navigates with j/k, searches with /
  ↓
User presses RET on existing session
  ↓
orchid-session-browser-select
  ↓
orchid-chat-open (session-id)
  ↓
  ├─> Create chat buffer
  ├─> Enable invisibility spec for collapsible sections
  ├─> Set up input area and assistant cursor
  └─> orchid-log-start-monitoring
      ↓
      ├─> Find log file (via CLI or convention)
      ├─> Create log buffer with auto-revert-tail-mode
      ├─> Register monitoring entry
      └─> Hook: after-revert-hook → orchid-log--process-new-content
  ↓
Chat buffer ready, monitoring active
```

## 2. Creating New Session

```
User: M-x orchid
  ↓
orchid-session-browser-show
  ↓
User navigates to "+ new (architect)"
  ↓
User presses RET
  ↓
orchid-session-browser-select
  ↓
orchid-chat-open-new "architect"
  ↓
  ├─> Create chat buffer
  ├─> Set orchid-chat--pending-new-session to "architect"
  ├─> Set temporary session-id to "pending"
  └─> Enable invisibility spec
  ↓
Chat buffer ready (no monitoring yet)
  ↓
User types first message, presses RET
  ↓
orchid-chat-send-input
  ↓
Detects pending new session
  ↓
orchid-chat--send-to-new-session
  ↓
orchid-core-send message nil :persona "architect"
  ↓
make-process: orchid send "message" --persona architect
  ↓
CLI creates new session, returns session-id
  ↓
orchid-chat--handle-new-session-result
  ↓
orchid-chat--activate-session (session-id session buffer)
  ↓
  ├─> orchid-session-register session
  ├─> setq orchid-chat--session-id session-id
  ├─> Clear orchid-chat--pending-new-session
  └─> orchid-log-start-monitoring-with-retry
      ↓
      Retry loop (up to 20 times, 1 second apart):
        ├─> Find log file
        ├─> Start auto-revert-tail-mode
        └─> Success → monitoring active
  ↓
Session created and monitoring established
```

## 3. Sending a Message

```
User types in chat buffer input area
  ↓
User presses RET
  ↓
orchid-chat-send-input
  ↓
orchid-history-add (save to history)
  ↓
orchid-chat--display-user-message (collapsed user stub)
  ↓
orchid-chat--prepare-for-response (separator + cursor setup)
  ↓
Check session type:
  ├─> Existing: orchid-chat--send-to-existing-session
  └─> New: orchid-chat--send-to-new-session
  ↓
make-process: orchid send "message" -s session-id
  ↓
Claude Code receives message
```

## 4. Receiving a Response (with Parsing)

```
Claude Code processes request
  ↓
Writes JSON events to log file
  ↓
auto-revert-tail-mode detects change
  ↓
after-revert-hook fires
  ↓
orchid-log--process-new-content
  ↓
For each new line:
  ├─> Extract event-id (UUID or tool_use_id)
  ├─> Check if already seen (deduplication)
  ├─> If duplicate → skip
  └─> If new:
      ├─> Mark as seen in hash table
      ├─> orchid-log-parse-line
      └─> orchid-parser-parse-json (dispatcher)
          ↓
          Check event type, dispatch to parser:
          ├─> "user" → orchid-parser-user-parse
          ├─> "assistant" → orchid-parser-assistant-parse
          ├─> "tool_use" → orchid-parser-tool-use-parse
          └─> Unknown → default format
          ↓
          Parser returns plist:
            :event-type 'assistant
            :display "formatted text with collapsible sections"
          ↓
          Callback: orchid-chat-insert-log-line
          ↓
          Insert at orchid-chat--assistant-cursor
          ↓
          orchid-chat--register-collapsible-sections
            ↓
            Scan for orchid-collapsible-id properties
            ↓
            Add each section-id to buffer-invisibility-spec
          ↓
  Content appears in chat buffer
```

## 5. Toggling Collapsible Section

```
User positions cursor on collapsible section
  ↓
User presses TAB
  ↓
orchid-chat-handle-tab
  ↓
orchid-collapsible-toggle-at-point
  ↓
Get orchid-collapsible-id property at point
  ↓
orchid-collapsible--toggle-section section-id
  ↓
Find stub region:
  ├─> Get current state (collapsed/expanded)
  └─> Toggle to new state
  ↓
Update stub properties:
  └─> orchid-collapsible-state → new-state
  ↓
Find detail region(s) with same section-id
  ↓
Update invisible property:
  ├─> If collapsed → set 'invisible to section-id
  └─> If expanded → set 'invisible to nil
  ↓
Section visibility toggles
```

## 6. Session Browser Operations

### Searching Sessions

```
User: / or a in session browser
  ↓
orchid-session-browser-search
  ↓
orchid-session-browser--mode set to 'search
orchid-session-browser-search-map installed as local keymap
  ↓
User types characters
  ↓
orchid-session-browser-search-self-insert
  ↓
Append char to orchid-session-browser--search-query
  ↓
orchid-session-browser--populate
  ↓
orchid-session-browser--make-browser (passes :search query, :filter-fn)
  ↓
seek-filtered-rows → orchid-session-browser--filter per session
  ↓
orchid-browser--fuzzy-match query (label + status + updated_at)
  ↓
seek-render renders filtered + highlighted results
  ↓
User: RET or ESC → orchid-session-browser-search-exit
User: d or C-g  → orchid-session-browser-search-clear (resets query)
```

### Marking and Deleting Sessions

```
User: D on session (mark for deletion)
  ↓
orchid-session-browser-mark-for-deletion
  ↓
puthash session-id 'delete marked-sessions
  ↓
orchid-session-browser--populate (shows "D" indicator)
  ↓
User: D on another session
  ↓
(repeat marking)
  ↓
User: x (execute marks)
  ↓
orchid-session-browser-execute
  ↓
Confirm: "Execute N marked operation(s)?"
  ↓
For each marked session:
  ├─> (delete) orchid-core-delete session-id
  │    ↓
  │    make-process: orchid delete --id session-id
  └─> (kill) orchid-core-stop session-id
       ↓
       make-process: orchid stop --id session-id
  ↓
remhash succeeded-ids from marked-sessions
  ↓
orchid-session-browser-refresh
  ↓
orchid-session-browser--populate
  ↓
Sessions removed from list (failed marks preserved)
```

### Status-Driven Refresh

```
Session status changes (process starts/stops)
  ↓
orchid-session-notify-status-change (session-id running)
  ↓
orchid-session-status-change-functions hook fires
  ↓
orchid-session-browser--on-status-change (session-id running)
  ↓
Check if browser buffer is live and visible
  ↓
  ├─> Not visible → no-op
  └─> Visible:
      Compute visible rows (seek-filtered-rows + scroll offset)
        ↓
        If session-id is in visible rows:
          ├─> orchid-session-browser--invalidate-row session-id
          └─> orchid-session-browser--populate
            ↓
            Browser redraws only when affected row is on screen
```

## 7. Input History

```
User presses M-p in chat input area
  ↓
orchid-history-previous
  ↓
Read from orchid-chat--input-history ring
  ↓
Move backward in history
  ↓
Replace input area with historical message
  ↓
User presses M-p again → older message
User presses M-n → newer message
```

## Component Communication

```
Chat Buffer
  ├─ send message ──────────> CLI Wrapper
  ├─ insert parsed events <──── Log Monitor
  ├─ toggle collapsible ─────> Collapsible Sections
  ├─ history navigation ─────> Input History
  └─ get session info ───────> Session Manager

Session Browser
  ├─ list sessions ──────────> Session Manager
  ├─ open chat ──────────────> Chat Buffer
  ├─ delete sessions ────────> CLI Wrapper
  ├─> fetch personas ────────> CLI Wrapper
  └─ auto-refresh ───────────> Session Manager

Session Manager
  ├─ list sessions ──────────> CLI Wrapper
  ├─ track buffers <─────────> Chat Buffer
  └─ track monitoring <──────> Log Monitor

Log Monitor
  ├─ watch file ─────────────> auto-revert-tail-mode
  ├─ parse lines ────────────> Parser Registry
  │    └─> Dispatch to parsers:
  │         ├─> User Parser
  │         ├─> Assistant Parser
  │         └─> Tool Use Parser
  ├─ deduplicate events ─────> Hash table (seen events)
  └─ callback ───────────────> Chat Buffer

Parser Registry
  ├─ register parsers <──────> Parser Modules
  ├─ dispatch events ────────> Specific Parsers
  └─ create collapsible ─────> Collapsible Sections

Collapsible Sections
  ├─ create sections ────────> Text Properties
  ├─ manage visibility ──────> Buffer Invisibility Spec
  └─ toggle at point <───────> Chat Buffer (TAB key)

CLI Wrapper
  ├─ execute commands ───────> orchid CLI
  ├─ send messages ──────────> Claude Code
  ├─ list/remove sessions ───> Session Management
  └─ list personas ──────────> Session Browser
```

## Error Handling Flow

```
CLI command fails
  ↓
orchid-core-* callback receives :success nil
  ↓
Chat Buffer: orchid-chat-insert-system-message
  ↓
User sees error in chat
```

```
Log file not found
  ↓
orchid-log-start-monitoring-with-retry
  ↓
Retry loop (up to 20 times, 1 second apart)
  ↓
  ├─> Success → monitoring starts
  └─> Failure → error message to user
```

```
New session creation times out
  ↓
orchid-log--try-start-monitoring
  ↓
Retry loop (up to 20 times, 1 second apart)
  ↓
  ├─> Session found → monitoring starts
  └─> Timeout → error message in chat buffer
```

## Next Steps

See:
- [Architecture Overview](overview.md) - Component summary
- [Chat Buffer](chat-buffer.md) - Primary UI details
- [Log Monitor](log-monitor.md) - Parsing and deduplication
- [Session Browser](session-browser.md) - Session management UI
- [Collapsible Sections](collapsible.md) - UI component details
