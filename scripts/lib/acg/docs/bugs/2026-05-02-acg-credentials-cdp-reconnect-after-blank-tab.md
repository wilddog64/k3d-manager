# Bug: CDP contexts() still empty after blank-tab recovery — reconnect required

**Date:** 2026-05-02
**Branch:** `fix/acg-credentials-cdp-reconnect`
**File:** `playwright/acg_credentials.js`

---

## Before You Start

1. `git pull origin fix/acg-credentials-cdp-reconnect` in the lib-acg repo
2. Read `memory-bank/activeContext.md` and `memory-bank/progress.md`
3. Read `playwright/acg_credentials.js` lines 186–214 in full before touching anything

---

## Problem

`make up` still prints the INFO fallback and exits 1 even after PR #7 shipped the blank-tab
recovery (PUT `/json/new`).

**Symptom in make output:**

```
 - [pid=70641] <gracefully close end>
INFO: [acg] Copy the credentials block from the Pluralsight sandbox page, then run:
INFO: [acg]   source scripts/plugins/acg.sh && pbpaste | acg_import_credentials
make: *** [up] Error 1
```

The `[pid=70641] <gracefully close end>` is Playwright's log for a browser it launched
exiting — it only appears when `launchPersistentContext` was taken and then
`browserContext.close()` ran in `finally`. This proves the blank-tab recovery silently
failed and the code fell through.

---

## Root Cause

`_cdpBrowser.contexts()` is **not a live query**. It returns Playwright's internal
`BrowserContext` list, which is populated only at `connectOverCDP` time via
`Target.getTargets`. When PUT `/json/new` creates a blank tab, Chrome fires
`Target.targetCreated` over the WebSocket, but Playwright does not materialize a new
`BrowserContext` entry for the default context from that event when no context existed at
connection time.

Result: the PUT succeeds (HTTP 200, Chrome opens the tab), but `_cdpBrowser.contexts()`
still returns `[]` after the 500ms wait. `if (!browserContext)` fires, `_cdpBrowser` is
disconnected, code falls to `launchPersistentContext`. CDP Chrome is still running and
holds `SingletonLock` on the profile — the newly launched Chrome (PID 70641) cannot
acquire the profile, exits gracefully, and Node exits 1.

---

## Fix

After PUT `/json/new` + 500ms, **disconnect and reconnect** instead of re-querying the
stale `contexts()`. A fresh `connectOverCDP` re-runs `Target.getTargets` and sees the
new target, correctly materializing the default `BrowserContext`.

### Change 1 — `playwright/acg_credentials.js`: reconnect after blank tab

**Exact old block (lines 199–205):**

```javascript
          await new Promise(r => setTimeout(r, 500));
          const _refreshedContexts = _cdpBrowser.contexts();
          if (_refreshedContexts.length > 0) {
            browserContext = _refreshedContexts[0];
            console.error('INFO: Default Chrome context now accessible after blank tab.');
          }
```

**Exact new block:**

```javascript
          await new Promise(r => setTimeout(r, 500));
          try { await _cdpBrowser.disconnect(); } catch {}
          _cdpBrowser = await chromium.connectOverCDP(CDP_URL);
          const _refreshedContexts = _cdpBrowser.contexts();
          if (_refreshedContexts.length > 0) {
            browserContext = _refreshedContexts[0];
            console.error('INFO: Default Chrome context now accessible after blank tab + reconnect.');
          }
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_credentials.js` | Replace stale `contexts()` re-query with disconnect + reconnect (4-line change) |

---

## Rules

- `node --check playwright/acg_credentials.js` — zero errors
- Code change: `playwright/acg_credentials.js` only; memory-bank updates are also required (see DoD)

---

## Definition of Done

- [ ] `try { await _cdpBrowser.disconnect(); } catch {}` added before reconnect
- [ ] `_cdpBrowser = await chromium.connectOverCDP(CDP_URL);` replaces stale `contexts()` call
- [ ] `_refreshedContexts` comes from the fresh connection's `contexts()`
- [ ] `node --check playwright/acg_credentials.js` passes
- [ ] Committed and pushed to `fix/acg-credentials-cdp-reconnect`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(acg): reconnect CDP after blank tab to force context re-discovery
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any code file other than `playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `fix/acg-credentials-cdp-reconnect`
- Do NOT increase the setTimeout beyond 500ms
- Do NOT remove the `if (!browserContext)` disconnect guard added in PR #7
