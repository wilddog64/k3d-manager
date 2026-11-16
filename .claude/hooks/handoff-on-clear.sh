#!/usr/bin/env bash
set -euo pipefail

file="${CLAUDE_PROJECT_DIR:-.}/memory-bank/activeContext.md"
[[ -f "$file" ]] || exit 0

handoff="$(awk '/^## /{n++} n==1' "$file")"
[[ -n "$handoff" ]] || exit 0

limit=9000
if (( ${#handoff} > limit )); then
  handoff="${handoff:0:limit}

[truncated at ${limit} characters; read the first section of memory-bank/activeContext.md for the rest]"
fi

jq -n --arg h "$handoff" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: ("Session started after /clear. Handoff from memory-bank/activeContext.md (first section); resume from it and verify live state before acting:\n\n" + $h)
  }
}'
