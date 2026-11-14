#!/usr/bin/env bash
set -euo pipefail

input="$(cat)"
log_dir="${K3DM_CLAUDE_CLEAR_LOG_DIR:-${HOME}/.local/share/k3d-manager}"
mkdir -p "$log_dir"

transcript="$(jq -r '.transcript_path // empty' <<<"$input")"
context_tokens=null
if [[ -n "$transcript" && -f "$transcript" ]]; then
  context_tokens="$(tail -n 200 "$transcript" | jq -s '[.[] | select(.type == "assistant") | .message.usage // empty | (.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)] | last // null' 2>/dev/null || echo null)"
fi

jq -c --argjson ts "$(date +%s)" --argjson ctx "${context_tokens:-null}" '{
  ts: $ts,
  event: .hook_event_name,
  kind: (.reason // .source),
  session_id: .session_id,
  cwd: .cwd,
  context_tokens: $ctx
}' <<<"$input" >>"$log_dir/claude-session-clears.jsonl"
