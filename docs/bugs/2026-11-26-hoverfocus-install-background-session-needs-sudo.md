# Bug: HoverFocus `make install` from an SSH session does not restart the agent and asks for sudo instead

**Status:** OPEN — captured, not triaged
**Priority:** P3
**Introduced by:** HoverFocus v0.0.2 F1 (install target)
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-26
**Classified:** pending (Argon, from this doc alone)
**Prior art:** none (exact-slug glob: no `docs/bugs/*hoverfocus*`; `make find-similar-docs` retrieval unavailable)
**Severity:** low — files are installed but the old binary keeps running until the operator runs two `sudo launchctl asuser` commands
**Filed:** 2026-11-26, operator: "I consider these are bugs" (U2 E2 setup on m2)
**Component:** HoverFocus `Makefile` `install` target (lines 71-78)

## Symptom

From SSH (`launchctl managername` = `Background`), `make install` prints "not a GUI login session … the agent is not
loaded" and two `sudo launchctl asuser 501 launchctl bootout/bootstrap` commands, then exits 0.

## Proof of a no-sudo path (m2, macOS 26.5.1, 2026-11-26, Claude over SSH)

With the agent already loaded in `gui/501`, `launchctl kickstart -k gui/501/com.wilddog64.hoverfocus` from the SSH
session → rc 0, pid 35871 → 54312, `state = running`. The gui domain is also readable (`launchctl print` OK).

## Fix options (for triage)

1. Non-Aqua session and the service is already loaded in `gui/$UID`: `kickstart -k` it (picks up the new binary; the
   plist path is unchanged) instead of printing the sudo commands.
2. Not loaded: keep today's message (bootstrap into a gui domain from Background still needs `asuser`).

Test: stub `launchctl` with `managername` → Background and `print` → loaded; assert `kickstart -k` is called and no
`sudo` text is printed. Red on current `v0.0.3`.
