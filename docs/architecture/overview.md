# Architecture Overview

## What is Orchid?

Orchid is an Emacs package that provides an **IRC-style chat interface** for Claude Code. You open a chat buffer for a session, type messages at the bottom, and watch Claude's responses stream in from monitored log files.

## Why This Architecture?

- **Chat-First**: Natural conversation flow, familiar IRC/ERC-style UX
- **File-Based**: No daemons, no HTTP - just files, processes, and `auto-revert-tail-mode`
- **CLI Integration**: Leverages existing `orchid` CLI tool as source of truth
- **Modular Parsing**: Registry-based system for extensible event handling
- **Smart UI**: Collapsible sections and deduplication for clean conversations

## High-Level Data Flow

```
User types in chat buffer
    ↓
Message sent via `orchid send` CLI
    ↓
Claude Code processes request, writes to log file
    ↓
Emacs monitors log with auto-revert-tail-mode
    ↓
New log lines parsed by modular parser system
    ↓
Formatted updates inserted into chat buffer
    ↓
Long content auto-collapsed (TAB to expand)
```

## Core Components

1. **[Chat Buffer](chat-buffer.md)** - Primary UI, IRC-style with collapsible sections
2. **[Log Monitor](log-monitor.md)** - Real-time streaming with deduplication
3. **[CLI Wrapper](cli-wrapper.md)** - Execute `orchid` commands (send, list, remove, etc.)
4. **[Session Manager](session-management.md)** - Track sessions in Emacs memory
5. **[Session Browser](session-browser.md)** - Full-featured session selection UI
6. **[Collapsible Sections](collapsible.md)** - Expandable/collapsible UI elements
7. **[Data Flows](data-flows.md)** - End-to-end event flow diagrams

## Component Dependencies

```
orchid-chat.el (PRIMARY INTERFACE)
  ├─> orchid-core.el (send messages)
  ├─> orchid-log.el (receive updates)
  │    └─> orchid-parsers.el (parse events)
  │         └─> parsers/* (event-specific handlers)
  ├─> orchid-history.el (input history)
  ├─> orchid-processing-indicator.el (visual feedback)
  ├─> orchid-collapsible.el (UI sections)
  └─> orchid-session.el (track state)

orchid-session-browser.el (ENTRY POINT)
  └─> orchid-session.el (data source)
```

## User Flow

```
M-x orchid
  → Session browser opens (search box + sessions)
  → User types to filter (optional)
  → User selects session or creates new with persona
  → Chat buffer opens
  → Log monitoring starts automatically
  → User types message, presses RET
  → Response streams in real-time
  → Long tool outputs auto-collapsed
  → Press TAB on collapsed sections to expand
```

## Key Design Decisions

### 1. Chat Buffer is Primary Interface
You spend your time in the chat buffer, not in menus. IRC-style input at bottom, conversation scrolls above.

### 2. Session Browser, Not Menu
Direct buffer-based selection instead of fuzzy menu + forms. See all sessions at once, search instantly, create inline.

### 3. Modular Parser System
Registry maps event types to handler functions. Each event type has its own parser module in `parsers/`. Adding new events: create new parser, register it.

### 4. Event Deduplication
Log monitor tracks seen events by UUID to prevent repeated content when Claude includes context from earlier messages.

### 5. Collapsible UI Sections
Long tool outputs start collapsed showing just a stub. Press TAB to expand/collapse. Uses text properties and `invisible` spec.

### 6. Two-Cursor System
Chat buffer maintains two cursors:
- **Input marker**: Start of user input area (bottom)
- **Assistant cursor**: Where assistant responses are inserted (grows upward)

Clean separation of user input from streamed responses.

### 7. CLI Wrapper, Not Reimplementation
`orchid` CLI is source of truth. Emacs wraps it with `orchid-core.el` for sync/async execution. Don't reimplement logic.

### 8. File-Based Monitoring
`auto-revert-tail-mode` watches log files. No polling daemons, no HTTP, no websockets. Simple and reliable.

## Module Sizes

For current file counts and line counts, run `wc -l lisp/*.el lisp/**/*.el`.

## Next Steps

- Read component docs for detailed designs
- Check `lisp/*.el` for implementation details
