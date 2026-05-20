# Retrospective — PR #14

**Date:** 2026-05-19
**Milestone:** fix(acg-extend): CDP browser disconnect hang
**PR:** #14 — merged to main (`b7d1dd7`)
**Participants:** Claude, Codex, Copilot

## What Went Well
- Root cause identified quickly: open CDP WebSocket keeping Node event loop alive
- Codex applied the finally block fix correctly on first attempt (node --check passed)
- Copilot caught 5 documentation accuracy issues (memory-bank descriptions, bug spec wording, "Do NOT create PR" contradiction)
- All Copilot threads resolved before merge

## What Went Wrong
- Codex initially committed the memory-bank update to k3d-manager instead of lib-acg — had to revert and redo in the correct repo
- Bug spec "What NOT to Do" included "Do NOT create a PR" (a Codex-handoff guard), which contradicts the repo's PR workflow — Copilot caught this

## Process Rules Added
- Bug spec "What NOT to Do" section must not include "Do NOT create a PR" — that is a Codex-handoff guard that belongs only in handoff blocks, not in committed bug docs
- Bug spec "Rules" section: use "Code change limited to <file>; CHANGELOG and memory-bank updates are required documentation" instead of "No other files touched"

## Decisions Made
- `_cdpBrowser.disconnect()` is the correct cleanup for CDP-attached sessions; `close()` would kill Chrome
- `browserContext.close()` remains correct for `launchPersistentContext` sessions
- lib-acg upstream fix is the authoritative source; k3d-manager subtree copy gets the fix on next subtree pull

## Theme
A one-line finally block fix that unblocked make up from hanging. The real complexity was workflow discipline: the fix needed to land upstream in lib-acg (not just in the k3d-manager subtree copy), and Codex initially committed to the wrong repo. Copilot's review was thorough — five documentation accuracy findings, all legitimate, all addressed before merge.
