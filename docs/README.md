# Orchid

An Emacs interface for the Orchid CLI with an IRC-style chat experience.

## Quickstart

1. Install the `orchid` CLI and ensure it is in your PATH:
   ```bash
   orchid --version
   ```

2. Clone and load the package:
   ```bash
   git clone https://github.com/yourusername/orchid.git ~/.emacs.d/lisp/orchid
   ```
   ```elisp
   (add-to-list 'load-path "~/.emacs.d/lisp/orchid")
   (require 'orchid)
   ```

3. Open the session browser:
   ```
   M-x orchid
   ```

## Summary

Orchid wraps the `orchid` CLI to give you an IRC-style chat buffer in Emacs.
Sessions are selected from a full-window browser; responses stream in via log file monitoring.
Version 1.0.0 — all planned features are complete.

## Chat Buffer Keybindings

| Key       | Action                      |
|-----------|-----------------------------|
| `RET`     | Send message                |
| `S-RET`   | Insert newline (multi-line) |
| `M-p`     | Previous input (history)    |
| `M-n`     | Next input (history)        |
| `C-c C-l` | Show session browser        |
| `C-c C-q` | Close chat                  |
| `TAB`     | Toggle collapsed section    |

## Session Browser Keybindings

| Key       | Action                            |
|-----------|-----------------------------------|
| `RET`     | Open selected session             |
| `n`       | New session (with persona)        |
| `D`       | Mark for deletion                 |
| `S`       | Mark for kill                     |
| `u`       | Unmark                            |
| `x`       | Execute marks (with confirmation) |
| `/` / `a` | Incremental search                |
| `d`       | Clear search                      |
| `r` / `g` | Refresh from CLI                  |
| `q`       | Quit browser                      |
| `j` / `k` | Navigate down / up                |
| `p`       | Navigate up (alias for `k`)       |
| `J` / `K` | Page down / up                    |

## Entry Points

```
M-x orchid                    — open session browser (main entry point)
M-x orchid-open-session       — open session by ID or label
M-x orchid-new-session        — new session with persona selection
M-x orchid-list-sessions      — print available sessions to echo area
M-x orchid-check-cli          — verify orchid CLI is found and working
```

## Troubleshooting

**CLI not found:** Run `M-x orchid-check-cli`. Set `orchid-core-cli-path` if the binary is not in PATH.

**No responses appearing:**
1. Check log file manually: `tail -f ~/.config/orchid/conversations/<id>/conversation.jsonl`
2. Verify auto-revert is running: `M-x describe-mode` in log buffer
3. Check for errors in `*Messages*` buffer

## Links

- [Architecture overview](architecture/overview.md)
- [Module organization](MODULE-ORGANIZATION.md)
- [CLI guide](cli-guide/README.md)
- [Development guides](development/)

## License

MIT
