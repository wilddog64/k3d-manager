# Retrospective — PR #12 (fix: acg_extend exit-0 on stale toast)

**Date:** 2026-05-17
**PR:** #12 — fix: exit 0 when Session extended toast visible at acg_extend.js startup
**PR #12 merged to:** main
**Participants:** Claude, Copilot

## What Went Well
- Root cause identified quickly: addLocatorHandler + page.mouse.click() in CDP session creates infinite loop when toast is already visible
- Copilot caught process.exit(0) bypassing finally block — fixed to return before merge
- Clean one-line fix: stale toast at startup = extension already succeeded, return early

## What Went Wrong
- Initial fix used process.exit(0) which bypasses finally block and leaks Chrome context — Copilot caught it
- Subtree workflow: attempted to fix directly in k3d-manager subtree copy instead of lib-acg upstream first (reversed immediately)

## Process Rules Added
- Never edit files under `scripts/lib/acg/` in k3d-manager directly — always fix in lib-acg upstream, push, then subtree pull
- Use `return` not `process.exit(0)` inside async try blocks — process.exit bypasses finally cleanup

## Decisions Made
- Stale toast detection: treat any visible "Session extended" toast at startup as success signal (toast auto-dismisses in seconds; if still visible when script starts, it's from the current session)
- CDP + page.mouse.click() is unreliable without OS focus — don't add more mouse.click dismiss attempts

## Theme
A one-line hang fix that revealed two process lessons: don't edit subtrees in-place, and process.exit inside a try block skips finally cleanup. Copilot caught the exit issue before merge. The fix is minimal and correct.
