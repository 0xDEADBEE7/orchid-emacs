#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Production ==="
cloc "$REPO_ROOT/orchid.el" "$REPO_ROOT/lisp/" --quiet

echo "=== Tests ==="
cloc "$REPO_ROOT/test/" --quiet
