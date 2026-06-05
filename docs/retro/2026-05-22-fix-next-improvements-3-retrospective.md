# Retrospective — fix/next-improvements-3

**Date:** 2026-05-22
**Milestone:** Extend Your Session modal robustness + LaunchDaemon plist idempotency
**PR:** #25 — merged to main (`2e698cf`)
**Participants:** Claude, Codex, Copilot

## What Went Well
- Codex implemented both the nav click fix and restart flow fix cleanly with exact commit messages
- Copilot caught doc wording issues (DoD constraint conflicts with repo workflow guidance)
- Background watcher approach identified and implemented — modal is time-triggered not action-triggered

## What Went Wrong
- Initial bug specs described the modal as action-triggered (appeared after specific clicks) — root cause is time-triggered; any point in the script can be affected
- First spec for acg_restart.js used "Do NOT create a PR" in What NOT to Do — contradicts repo workflow for committed specs (Copilot caught this)
- acg_restart.js fix was point-in-time; correct fix is background watcher polling every 2s

## Process Rules Added
- Bug spec "What NOT to Do" must NOT include "Do NOT create a PR" — this is a handoff-only guard, not a spec rule
- Bug spec DoD "No other files modified" → use "Code change limited to <file>; CHANGELOG/docs updates may also be required"
- Retro files must include merge commit SHA on the PR line

## Decisions Made
- Background watcher (`_startExtendDialogWatcher`) is the canonical fix for time-triggered modals — poll `_dismissExtendYourSessionDialog` every 2s from script start; fire-and-forget
- Point-in-time dismiss calls kept as belt-and-suspenders

## Theme
Fixed "Extend Your Session" modal blocking `make up` in two code paths (SPA nav click and sandbox restart panel expand). Root cause: modal is time-triggered by sandbox TTL expiry, can appear at any point. Three fixes shipped: (1) hoist `_dismissExtendYourSessionDialog` before nav block in acg_credentials.js, (2) add dismiss call after Open Sandbox click in acg_restart.js, (3) background watcher polling every 2s throughout entire script run. Also spec'd LaunchDaemon plist idempotency fix for passwordless `make up` pipeline.
