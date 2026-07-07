# Session Browser Component

## Purpose

A full-window buffer for browsing, searching, and managing sessions. Primary entry point via `M-x orchid`.

## Overview

```
┌────────────────────────────────────────┐
│  *orchid-sessions*                     │
├────────────────────────────────────────┤
│  Search: _                             │
│                                        │
│  my-project        [running]           │
│  debug-session     [idle]              │
│  experiment        [idle]              │
│                                        │
│  RET:open  n:new  D:delete  S:kill     │
│  u:unmark  x:execute  /:search  q:quit │
└────────────────────────────────────────┘
```

## Features

- **Incremental search**: Press `/` or `a`, type to filter sessions in real-time
- **Mark and execute**: Mark sessions for deletion (`D`) or kill (`S`), execute with `x`
- **New session**: Press `n` to open a new chat with optional persona selection
- **Status-driven refresh**: Redraws only affected rows when a session's running status changes
- **Full window**: Opens with `switch-to-buffer` (not a side window)

## Public API

```elisp
(orchid-session-browser-show)
;; Show session browser (switch-to-buffer)

(orchid-session-browser-select)
;; Open chat buffer for selected session

(orchid-session-browser-new)
;; Start new session with persona selection via completing-read

(orchid-session-browser-refresh)
;; Fetch session list from CLI and repopulate browser

(orchid-session-browser-quit)
;; Kill browser buffer and quit window
```

## Keybindings

```elisp
(defvar orchid-session-browser-mode-map ...)

;; RET  orchid-session-browser-select         open selected session
;; n    orchid-session-browser-new            new session (with persona)
;; r/g  orchid-session-browser-refresh        refresh from CLI
;; D    orchid-session-browser-mark-for-deletion
;; S    orchid-session-browser-mark-for-kill
;; u    orchid-session-browser-unmark
;; x    orchid-session-browser-execute        execute marks (with yes-or-no-p)
;; /    orchid-session-browser-search         incremental search
;; a    orchid-session-browser-search         (alias for /)
;; d    orchid-session-browser-search-clear   clear search
;; j/p  orchid-session-browser-move-down/up   single row
;; J/K  orchid-session-browser-page-down/up   page at a time
;; q    orchid-session-browser-quit
```

## Implementation

### Major Mode

```elisp
(define-derived-mode orchid-session-browser-mode special-mode "Orchid-Sessions"
  "Major mode for browsing Orchid sessions."
  (setq truncate-lines t)
  (setq buffer-read-only t)
  ;; Buffer-local state initialised here
  ;; Status-change hook registered; removed on kill-buffer
  (add-hook 'orchid-session-status-change-functions
            #'orchid-session-browser--on-status-change))
```

### Display

```elisp
(defun orchid-session-browser-show ()
  "Show session browser buffer."
  (interactive)
  (let ((buffer (get-buffer-create orchid-session-browser-buffer-name)))
    (switch-to-buffer buffer)               ; full window, not side window
    (unless (eq major-mode 'orchid-session-browser-mode)
      (orchid-session-browser-mode))
    (orchid-session-refresh)
    (orchid-session-browser--populate)))
```

Rendering is delegated to the `seek` library via `orchid-session-browser--populate`.
A row-string cache (`orchid-session-browser--row-strings`) avoids redrawing rows
that have not changed.

### Search

Pressing `/` or `a` calls `orchid-session-browser-search`, which:
1. Sets `orchid-session-browser--mode` to `'search`
2. Installs `orchid-session-browser-search-map` via `use-local-map` (no evil state switch required)
3. Each character appended to `orchid-session-browser--search-query` triggers `orchid-session-browser--populate`
4. `seek` passes the query to `orchid-session-browser--filter`, which calls `orchid-browser--fuzzy-match`
   against the concatenation of label + status + updated_at

Press `RET` or `ESC` to exit search mode; press `d` or `C-g` to clear the query.

### Status-Driven Refresh

There is no polling timer. Instead, `orchid-session-browser--on-status-change` is
registered on `orchid-session-status-change-functions`. When called, it checks whether
the affected session is currently visible in the scroll window, and only redraws if so.

Use `r` / `g` to force a full CLI fetch (`orchid-session-browser-refresh`).

### Session Object

```elisp
;; Parsed from `orchid list`
(:id "abc123..."
 :label "my-project"
 :working-dir "/path/to/project"
 :persona "default"
 :updated_at "2024-01-01T00:00:00Z"
 :running t            ; set via orchid-session-notify-status-change
 :chat-buffer #<buffer> ; set if open in Emacs
 :log-buffer  #<buffer> ; set if monitoring
 :monitoring-p t)
```

## Integration Points

- **[Session Manager](session-management.md)**: Data source — reads session registry
- **[Chat Buffer](chat-buffer.md)**: Opens via `orchid-session-open` → `orchid-chat-open`
- **[CLI Wrapper](cli-wrapper.md)**: `orchid-core-list` fetches session data; `orchid-core-delete` / `orchid-core-stop` for marks execution

## Workflow

```
M-x orchid
  → orchid-session-browser-show
  → full window opens with session list
  → type / to filter, or RET to open, or n to create new
  → chat buffer replaces browser window
```
