# Retrospective — PR #7: CDP empty-contexts fix

**Date:** 2026-05-02
**PR:** #7 — merged to main (`027b5765`)
**Branch:** `fix/acg-credentials-cdp-empty-contexts`
**Participants:** Claude, Codex, Copilot

## What Went Well

- Root cause identified quickly: `curl -s http://localhost:9222/json/list` returning `[]` confirmed the CDP empty-contexts state in under 5 minutes
- Spec-before-implement discipline held: bug spec written in `docs/bugs/` before any code was touched, then handed to Codex
- Correction caught before PR: Claude reviewed Codex's diff character-by-character and spotted the missing `if (!browserContext)` guard before pushing the broken fix
- Copilot caught the GET→PUT issue: `http.get()` silently returning 405 from Chrome's `/json/new` would have made the fix a no-op at runtime; Copilot flagged it before merge
- All 6 Copilot threads addressed and resolved in one fix commit (`7c48e5d`) — CI green on first attempt after fix

## What Went Wrong

- **Codex dropped the `if (!browserContext)` guard** in commit `b5327fb` — the blank-tab block ran but immediately disconnected the browser even on success. Required a correction spec and second Codex pass.
- **Original spec used `http.get()` for `/json/new`** — Chrome requires PUT on current versions; this was not caught during spec writing and made it through two Codex commits before Copilot caught it
- **Two bug spec files** needed for one fix: the main spec + correction spec signals the initial spec was underspecified (the guard was implied but not stated explicitly)

## Process Rules Added

| Rule | Where |
|------|--------|
| When opening a Chrome DevTools `/json/new` tab: use `http.request({method:'PUT'})` + `req.end()`, never `http.get()` | Implicit — spec template |
| Guard disconnect behind `if (!context)` any time blank-tab recovery runs | Implicit — spec template |
| Rules section in bug specs must not say "no other files" when DoD requires memory-bank updates | Fixed in both specs this PR |

## Decisions Made

- Blank-tab leak (about:blank tab remaining open after recovery) deferred as out-of-scope for this PR — functional fix first, cleanup tracked separately
- `http` module used instead of `fetch` or `playwright` internal API to keep the implementation simple and dependency-free

## Theme

A `make up` failure that looked like a timeout problem was actually a CDP state problem: Chrome with no open tabs exposes an empty context list, which caused fallthrough to a profile-locked code path. The fix was straightforward (open a blank tab, re-query), but required three commits to get right: Codex dropped the disconnect guard, and the initial spec used the wrong HTTP method. Copilot caught the HTTP verb error before it shipped — the kind of subtle, version-specific behavioral detail that spec authors miss.
