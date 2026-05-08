# Retrospective — PR #8: CDP reconnect after blank tab

**Date:** 2026-05-02
**PR:** #8 — merged to main (`30917444`)
**Branch:** `fix/acg-credentials-cdp-reconnect`
**Participants:** Claude, Codex, Copilot

## What Went Well

- Root cause was precise: `_cdpBrowser.contexts()` returns a stale empty list post-connect even after a new tab is created via PUT `/json/new` — Playwright does not materialize a BrowserContext from `Target.targetCreated` events. Disconnect + reconnect gives a fresh view.
- Fix was small and targeted: 4-line change in `acg_credentials.js` — disconnect after blank tab, reconnect, re-query contexts.
- No Copilot findings on this PR — clean first submission.

## What Went Wrong

- PR branched from a state before PR #7 was squash-merged to main, so the reconnect fix was developed without the PUT `/json/new` method already in place — required rebasing onto main post-merge.
- Memory-bank not updated with PR #8 retro at merge time (this retro is being written retroactively as part of the PR #9 post-merge cleanup).

## Decisions Made

- Reconnect is unconditional after blank-tab creation: even if `contexts()` returned entries, a fresh connection is cheaper than debugging Playwright's post-connect event handling.
- No wait added between disconnect and reconnect — the `connectOverCDP` call itself acts as the retry gate.

## Theme

The blank-tab fix from PR #7 solved the wrong problem: the tab was created but Playwright still saw an empty context list because `contexts()` is not live. The real fix is that Playwright requires a fresh `connectOverCDP` call to observe tabs created after the initial connection. A small follow-on fix; CI green first pass.
