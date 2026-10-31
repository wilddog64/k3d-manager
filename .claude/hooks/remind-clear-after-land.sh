#!/usr/bin/env bash
set -euo pipefail

cmd="$(jq -r '.tool_input.command // empty')"
case "$cmd" in
  *"k3dm-codex-dispatch land"*|*"make codex-land"*) ;;
  *) exit 0 ;;
esac

jq -n '{
  systemMessage: "Task landed. When this objective is fully verified (live evidence included), run /clear before starting the next one.",
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: "A task just landed. If its objective is complete (landed and live-verified), write the handoff into memory-bank/activeContext.md (objective, evidence, decisions, changed files, open questions, verification status) and then remind the operator to run /clear before the next objective. If live verification for this objective is still pending, finish it first in this session."
  }
}'
