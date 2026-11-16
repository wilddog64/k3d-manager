#!/usr/bin/env bash
set -euo pipefail

project="${CLAUDE_PROJECT_DIR:-$PWD}"
memory="${K3DM_CLAUDE_MEMORY_INDEX:-$HOME/.claude/projects/${project//\//-}/memory/MEMORY.md}"
memory_limit="${K3DM_MEMORY_INDEX_MAX_BYTES:-9000}"
claude_limit="${K3DM_CLAUDE_MD_MAX_BYTES:-11000}"

over=()
for pair in "$memory:$memory_limit" "$project/CLAUDE.md:$claude_limit"; do
  file="${pair%:*}"
  limit="${pair##*:}"
  [[ -f "$file" ]] || continue
  size="$(wc -c <"$file" | tr -d ' ')"
  if (( size > limit )); then
    over+=("$file is ${size} bytes (budget ${limit})")
  fi
done

(( ${#over[@]} )) || exit 0

msg="Context budget exceeded: $(printf '%s; ' "${over[@]}")compress per /post-merge Step 7c at the next natural break (hub files for MEMORY.md; summaries plus [more] links for CLAUDE.md, shared blocks identical in AGENTS.md and GEMINI.md)."
jq -n --arg m "$msg" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $m}}'
