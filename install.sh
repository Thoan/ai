#!/usr/bin/env bash
# Install the skills and agents into ~/.claude (or a project's .claude with --project <dir>).
# Anything it would overwrite is moved to <dest>/backups/<timestamp>/ first.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude"
if [[ "${1:-}" == "--project" ]]; then
  DEST="$(cd "${2:?usage: install.sh [--project <dir>]}" && pwd)/.claude"
fi
STAMP="$(date +%Y%m%d-%H%M%S)"

install_one() {  # <source path> <dest path>
  if [[ -e "$2" ]]; then
    if diff -rq "$1" "$2" >/dev/null 2>&1; then echo "  same  ${2#"$DEST"/}"; return; fi
    # outside skills/ and agents/, so Claude Code never loads a backup as a duplicate
    local bak="$DEST/backups/$STAMP/${2#"$DEST"/}"
    mkdir -p "$(dirname "$bak")" && mv "$2" "$bak"
    echo "  backed up ${2#"$DEST"/} → ${bak#"$DEST"/}"
  fi
  cp -R "$1" "$2"
  echo "  installed ${2#"$DEST"/}"
}

mkdir -p "$DEST/skills" "$DEST/agents"
echo "skills → $DEST/skills"
for d in "$SRC"/skills/*/; do install_one "${d%/}" "$DEST/skills/$(basename "$d")"; done
echo "agents → $DEST/agents"
for f in "$SRC"/agents/*.md; do install_one "$f" "$DEST/agents/$(basename "$f")"; done
echo "done. Restart Claude Code (or start a new session) to pick them up."
