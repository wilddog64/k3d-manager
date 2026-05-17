# Retrospective — PR #9: Chrome SingletonLock collision fix

**Date:** 2026-05-03
**PR:** #9 — merged to main (`79a6acdd`)
**Branch:** `bug/chrome-singleton-lock-collision`
**Participants:** Claude, Codex

## What Went Well

- Root cause was well-understood before coding: the `chrome-cdp` launchd agent holds the profile lock, blocking interactive automation from launching Chrome with the same `--user-data-dir`.
- `_cdp_profile_in_use` uses `ps` + `awk` pattern matching — no process ID tracking needed, portable across Chrome binary names.
- SingletonLock removal is safe-guarded: only removed when `_cdp_profile_in_use` returns false, preventing removal of a live lock.

## What Went Wrong

- **`launchctl unload` used instead of `launchctl bootout`** — on macOS 15+ (Darwin 25+), `launchctl unload <plist>` is deprecated in favor of `launchctl bootout gui/$(id -u)/<label>`. The `2>/dev/null` silently masked any deprecation warnings or failures. Fixed in post-merge cleanup.
- **Plist file existence check was unnecessary** — `launchctl list <label>` already confirms the service is running; checking `[[ -f "${_CDP_CHROME_CDP_PLIST}" ]]` adds nothing and fails if the plist path is wrong. Removed in post-merge cleanup.
- **No retro written at merge time** — Codex merged and updated memory-bank but did not write a retro. Written retroactively.
- **Memory-bank `activeContext.md` still referenced `bug/chrome-singleton-lock-collision` as current branch** after merge. Stale `[ ] ACG extend surface timing gap` row left in `progress.md` even though PR #3 was merged.

## Process Rules Added

| Rule | Source |
|------|--------|
| Use `launchctl bootout "gui/$(id -u)/<label>"` for LaunchAgent lifecycle on macOS 15+ — never `launchctl unload` | launchctl deprecation on Darwin 25 |
| Codex must write retro at merge time — retro omission is a DoD failure | PR #9 retro omitted |

## Decisions Made

- 5-second wait cap after `bootout` is sufficient — the profile lock should release within 1–2 seconds of the agent stopping.
- Agent stop is no-op on non-Darwin (early return) — Linux CI environments are unaffected.

## Theme

A straightforward pre-flight cleanup fix that prevents Chrome's profile-lock error from blocking automation start. The implementation was correct in principle but used a deprecated API that silently failed. The main lesson: `launchctl unload` has been deprecated since macOS 13 — always use `bootout` on Darwin 25+. The fix was applied in post-merge cleanup (`fix/post-merge-pr9-cleanup`).
