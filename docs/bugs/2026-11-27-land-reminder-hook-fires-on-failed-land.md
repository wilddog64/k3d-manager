# Bug: the land reminder hook says "task landed" when the land failed or is still running

**Status:** OPEN — capture
**Priority:** P3
**Introduced by:** unknown
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-27
**Prior art:** not run (`make find-similar-docs` vector store unavailable: k3d cluster context absent); exact-slug glob found none
**Filed:** 2026-11-27, Claude, from the hook audit prompted by the AI Engineer talk (operator: "yes")

## Evidence

- `.claude/hooks/remind-clear-after-land.sh` matches the Bash command text (`*"k3dm-codex-dispatch land"*`,
  `*"make codex-land"*`) and always emits "Task landed …".
- 2026-11-27, `v1460-pytestvenv-flash`: it fired after three failed lands ("worktree has uncommitted changes", test
  command error, fast gate failure) and after a land sent to the background, before any landing.
- Effect: Claude is told to write a handoff and suggest `/clear` mid-objective; harmless only because Claude checked
  the land output.

## Fix outline

Fire only when the tool response contains the land's success line (`landed: <slug>`); read
`.tool_response` (stdout) with `jq`, and stay silent otherwise. Test: one fixture with `landed:` (fires), one with the
`[codex-dispatch] ERROR` output (silent), one backgrounded response (silent).

## Hook audit (same date)

No configured Claude Code hook gates work: all are reminders, counters or logs (user `~/.claude/settings.json`:
session-reset, tool-counter, weekly-quota reminder; project: this hook, session-clear logging, handoff-on-clear,
context-size check). The exit-code gotcha from the talk (a failing check exits 1, which only warns; exit 2 blocks) does
not apply today, and must be followed by any future gating hook.
