#!/usr/bin/env bash
set -euo pipefail

root="${CLAUDE_PROJECT_DIR:-.}"
file="$root/memory-bank/activeContext.md"
[[ -f "$file" ]] || exit 0

handoff="$(awk '/^## /{n++} n==1' "$file")"
[[ -n "$handoff" ]] || exit 0

limit=9000
if (( ${#handoff} > limit )); then
  handoff="${handoff:0:limit}

[truncated at ${limit} characters; read the first section of memory-bank/activeContext.md for the rest]"
fi

live="Live state (computed by the hook at $(date '+%Y-%m-%d %H:%M %Z'); trust this over the handoff where they differ):"

header_sha="$(git -C "$root" log -1 --format=%H -L1,1:memory-bank/activeContext.md 2>/dev/null | head -1 || true)"
if [[ "$header_sha" =~ ^[0-9a-f]{40}$ ]]; then
  since="$(git -C "$root" log --format='%h %s' "$header_sha..HEAD" -- 2>/dev/null || true)"
  count=0
  [[ -z "$since" ]] || count="$(printf '%s\n' "$since" | wc -l | tr -d ' ')"
  if (( count > 0 )); then
    live+="
- HANDOFF STALE: ${count} commit(s) since the START HERE header was last rewritten (${header_sha:0:8}). Reconcile before acting:
$(printf '%s\n' "$since" | head -25 | sed 's/^/    /')"
  else
    live+="
- Handoff header is current (no commits since ${header_sha:0:8})."
  fi
fi

dirty="$(git -C "$root" status --porcelain 2>/dev/null | head -10 || true)"
[[ -z "$dirty" ]] || live+="
- Uncommitted changes:
$(printf '%s\n' "$dirty" | sed 's/^/    /')"

if [[ -x "$root/bin/k3dm-codex-dispatch" ]]; then
  open="$("$root/bin/k3dm-codex-dispatch" open 2>/dev/null | head -10 || true)"
  live+="
- Open dispatches (bin/k3dm-codex-dispatch open): ${open:-none}"
fi

if hub="$(git -C "$root" rev-parse --short origin/deploy/hub 2>/dev/null)"; then
  ahead="$(git -C "$root" rev-list --count origin/deploy/hub..HEAD 2>/dev/null || echo '?')"
  live+="
- Hub: origin/deploy/hub = ${hub} (local ref, not fetched); HEAD is ${ahead} commit(s) ahead."
fi

if [[ -f "$root/memory-bank/progress.md" ]]; then
  live+="
- Last progress.md entries:
$(tail -n 5 "$root/memory-bank/progress.md" | cut -c1-300 | sed 's/^/    /')"
fi

jq -n --arg h "$handoff" --arg l "$live" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: ("Session started after /clear. Handoff from memory-bank/activeContext.md (first section); resume from it and verify live state before acting:\n\n" + $h + "\n\n" + $l)
  }
}'
