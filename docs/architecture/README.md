# Orchid Architecture Documentation

Complete architecture documentation for the Orchid Emacs package.

## Overview

Orchid is an Emacs interface for Claude Code providing:
- IRC-style chat buffer for conversations
- Real-time log streaming with smart parsing
- Session browser for managing conversations
- Collapsible UI sections for long content

## Quick Links

### Core Components
1. **[Overview](overview.md)** - Architecture summary and key concepts
2. **[Chat Buffer](chat-buffer.md)** - IRC-style primary interface
3. **[Log Monitor](log-monitor.md)** - Real-time log streaming with deduplication
4. **[CLI Wrapper](cli-wrapper.md)** - Execute `orchid` CLI commands
5. **[Session Manager](session-management.md)** - Track sessions in Emacs

### UI Components
6. **[Session Browser](session-browser.md)** - Full-featured session selection
7. **[Collapsible Sections](collapsible.md)** - Expandable/collapsible content

### Supporting Components
8. **[Data Flows](data-flows.md)** - End-to-end event flow diagrams

## Component Map

```
orchid.el (entry point)
  └─> orchid-session-browser.el
       └─> orchid-session.el
            └─> orchid-chat.el
                 ├─> orchid-core.el
                 ├─> orchid-log.el
                 │    └─> orchid-parsers.el
                 │         └─> parsers/
                 │              ├─> orchid-parser-registry.el
                 │              ├─> orchid-parser-assistant.el
                 │              ├─> orchid-parser-user.el
                 │              ├─> orchid-parser-utils.el
                 │              └─> orchid-parser-tool-use.el
                 ├─> orchid-history.el
                 ├─> orchid-processing-indicator.el
                 └─> orchid-collapsible.el
```

## Architecture Principles

- **Chat-First**: IRC-style chat buffer is primary interface
- **File-Based**: Monitor log files with `auto-revert-tail-mode`, no daemons
- **CLI Integration**: Wrap existing `orchid` CLI tool, don't reimplement
- **Extensible**: Pluggable parser registry for new event types
- **Simple UI**: Direct session browser, no complex menus or forms
- **Smart Updates**: Event deduplication prevents repeated content

## File Structure

```
orchid/
├── orchid.el                        # Package entry point
├── orchid-chat.el                   # Chat buffer (PRIMARY INTERFACE)
├── orchid-log.el                    # Log monitoring with deduplication
├── orchid-core.el                   # CLI wrapper
├── orchid-session.el                # Session tracking
├── orchid-session-browser.el        # Session selection UI
├── orchid-collapsible.el            # Collapsible UI sections
├── orchid-history.el                # Input history persistence
├── orchid-processing-indicator.el   # Visual feedback during operations
├── orchid-parsers.el                # Parser loader
└── parsers/
    ├── orchid-parser-registry.el    # Parser registration system
    ├── orchid-parser-utils.el       # Shared parser utilities
    ├── orchid-parser-assistant.el   # Assistant message formatting
    ├── orchid-parser-user.el        # User message formatting
    └── orchid-parser-tool-use.el    # Tool use event formatting
```

## Key Features

### Session Browser
- Instant fuzzy search across sessions
- Integrated persona selection for new sessions
- Multi-select for batch deletion
- Status-driven refresh: redraws when a session's running state changes

### Chat Buffer
- IRC-style input at bottom
- Two-cursor system for clean message insertion
- Collapsible sections for long tool outputs
- TAB to expand/collapse details
- M-p/M-n for input history

### Log Monitoring
- Event deduplication via UUID tracking
- Modular parser system with registry
- Retry logic for new sessions
- Smart position tracking

### Parser System
- Registry-based event routing
- Per-event-type handler modules
- Queue management for incomplete events
- Collapsible formatting for tool results

## User Workflow

```
M-x orchid
  → Session browser opens with search
  → Select session or create new with persona
  → Chat buffer opens
  → Log monitoring starts automatically
  → Type message, press RET
  → Response streams in real-time
  → Long content auto-collapsed (TAB to expand)
```

## Reading Order

### For Users
1. [Overview](overview.md) - Start here
2. [Chat Buffer](chat-buffer.md) - Learn the interface
3. [Session Browser](session-browser.md) - Manage sessions

### For Developers
1. [Overview](overview.md) - Architecture concepts
2. [CLI Wrapper](cli-wrapper.md) - External integration
3. [Log Monitor](log-monitor.md) - Real-time streaming
4. Component docs (in dependency order)

### For Contributors
1. [Overview](overview.md) - Big picture
2. [Log Monitor](log-monitor.md) - Most extensible area (parser system)
3. Specific component of interest

## Design History

### Refactor 00: Simplified UI
- Removed menu/forms system
- Replaced session-list with full-featured browser
- Integrated persona selection
- Added search and multi-select

### Refactor 01: Simplified Internals
- Removed config module (use defcustom)
- Removed error module (use standard error handling)
- Removed progress indicators (use processing-indicator)
- Simplified log parsers (modular registry)
- Simplified history (persistent file-based)

## Next Steps

- Read [Overview](overview.md) for architecture concepts
- See component docs (chat-buffer, log-monitor, cli-wrapper, session-management, session-browser, data-flows, collapsible) for implementation details
