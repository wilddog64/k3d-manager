# Bug: `make install` leaves a hand-started HoverFocus running the old build

**Status:** OPEN — capture
**Priority:** P3 (proposed, Claude) — test-time confusion: the new build is on disk but not running; workaround is quit and `launchctl kickstart -k`
**Introduced by:** pre-existing (`make install` manages only the LaunchAgent since v0.0.1)
**Should have been caught by:** none
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-25
**Prior art:** exact-slug glob over `docs/hoverfocus/bugs/` (no match); `make find-similar-docs` not run
**Filed:** 2026-11-25
**Detected by:** Claude, L4 live check on m2-air, 2026-11-25

## Observed

The operator had started HoverFocus by hand (`open ~/Applications/HoverFocus.app`, pid 59121, 19:58:47) during the U1
restart test, then pulled L4 and ran `make install` (binary rebuilt 20:03:06). `make install` booted out and
bootstrapped the LaunchAgent, but pid 59121 kept running the pre-L4 binary, so Slack and VS Code were first tested
against old code. After quitting it and `launchctl kickstart -k gui/$(id -u)/com.wilddog64.hoverfocus` (pid 60390,
20:07:21) the L4 check passed.

## Fix direction (for triage)

`make install` warns (or quits it) when a HoverFocus process is running that launchd does not own, e.g. compare
`pgrep -f HoverFocus.app/Contents/MacOS` with the agent's pid from `launchctl print`.
