# Collapsible Sections Component

## Purpose

Provides expandable/collapsible text sections using text properties and invisibility specs. Allows long tool outputs and detailed content to be collapsed into compact stubs, improving chat buffer readability.

## Overview

```
┌─────────────────────────────────────────────┐
│  Tool: Read file.txt [TAB to expand]        │  ← Collapsed
└─────────────────────────────────────────────┘

                    ↓ Press TAB

┌─────────────────────────────────────────────┐
│  Tool: Read file.txt [TAB to collapse]      │  ← Expanded
│  Read /path/to/file.txt                     │
│                                              │
│  Line 1: content here                       │
│  Line 2: more content                       │
│  ...                                         │
│  Line 100: end of file                      │
└─────────────────────────────────────────────┘
```

## Features

- **Text property-based**: No overlays, pure text properties
- **Buffer invisibility spec**: Leverages Emacs invisibility mechanism
- **Theme-aware**: Uses standard font-lock faces that adapt to themes
- **Unique IDs**: Each section gets unique identifier for independent toggling
- **Keyboard-driven**: TAB to toggle at point

## Public API

```elisp
(orchid-collapsible-create stub-text detail-text &optional initially-collapsed stub-face)
;; Create collapsible section with STUB-TEXT and DETAIL-TEXT
;; Returns formatted string with text properties
;; If INITIALLY-COLLAPSED is non-nil, starts collapsed

(orchid-collapsible-create-lazy stub-text detail-fn &optional initially-collapsed stub-face)
;; Create collapsible section where DETAIL-FN is called only on first expand
;; Use when detail content is expensive to format
;; Prefer this in parsers where detail text requires formatting work

(orchid-collapsible-toggle-at-point)
;; Toggle collapsible section at point
;; Returns t if section was toggled, nil if no section at point

(orchid-collapsible-report-stats)
;; Report statistics on collapsible sections in current buffer
```

## Usage Example

```elisp
;; Create collapsible tool output
(let ((stub "Tool: Read config.yaml")
      (details "Read /home/user/config.yaml\n\nserver:\n  port: 8080\n..."))
  (insert (orchid-collapsible-create stub details t)))

;; User presses TAB → section expands
;; User presses TAB again → section collapses
```

## Integration with Chat Buffer

The chat buffer must:
1. Enable invisibility in buffer setup
2. Register section IDs in invisibility spec as inserted
3. Bind TAB to handle collapsible sections

```elisp
;; In orchid-chat.el setup
(setq buffer-invisibility-spec '())
(add-to-invisibility-spec t)

;; TAB handler
(defun orchid-chat-handle-tab ()
  "Handle TAB key press."
  (interactive)
  (unless (orchid-collapsible-toggle-at-point)
    ;; Not on collapsible section
    (if (>= (point) orchid-chat--input-marker)
        (insert "\t")  ; In input area
      (message "Use TAB on collapsible sections to expand/collapse them"))))
```

## Design Rationale

### Why Text Properties Instead of Overlays?

Text properties persist when buffer content is saved/copied, making them more suitable for read-only content display. Overlays are better for transient UI elements.

### Why Invisibility Spec?

Emacs invisibility spec is the standard way to hide/show text. It integrates with:
- Search (invisible text skipped)
- Navigation (cursor jumps over invisible regions)
- Copy/paste (invisible text not copied by default)

### Why Unique IDs?

Each section needs a unique invisibility spec entry to toggle independently. Using symbols (`orchid-collapsible-1`, etc.) allows fine-grained control.

## Integration Points

- **[Chat Buffer](chat-buffer.md)**: Primary consumer, displays collapsible sections
- **[Log Parsers](log-monitor.md)**: Parsers create collapsible sections from events
- **Parser modules**: `orchid-parser-tool-use.el`, `orchid-parser-assistant.el`

## Next Steps

See:
- [Chat Buffer](chat-buffer.md) - Uses collapsible sections
- [Log Monitor](log-monitor.md) - Parsers create sections
- Reference: `lisp/orchid-collapsible.el` for full implementation
