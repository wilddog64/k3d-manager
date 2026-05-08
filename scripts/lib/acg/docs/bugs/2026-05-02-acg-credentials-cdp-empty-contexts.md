# Bug: acg_credentials_provision fails when CDP Chrome has no open tabs

**Date:** 2026-05-02
**Branch:** `fix/acg-credentials-cdp-empty-contexts`
**File:** `playwright/acg_credentials.js`

---

## Before You Start

1. `git pull origin fix/acg-credentials-cdp-empty-contexts` in the lib-acg repo
2. Read `memory-bank/activeContext.md` and `memory-bank/progress.md`
3. Read `playwright/acg_credentials.js` in full — understand the CDP connect block (lines ~168–200) before touching anything

---

## Problem

`make up` fails with:

```
INFO: [acg] Copy the credentials block from the Pluralsight sandbox page, then run:
INFO: [acg]   source scripts/plugins/acg.sh && pbpaste | acg_import_credentials
make: *** [up] Error 1
```

This happens every time CDP Chrome (PID launched by `make chrome-cdp`) is running but
has no open tabs — a common state after the machine has been idle for hours or days.

**Root cause:** Chrome's default browser context is not exposed by the CDP protocol
(`/json/list` returns `[]`) until at least one tab is open. `_cdpBrowser.contexts()`
therefore returns an empty array. The code treats this as "CDP not usable", disconnects
from CDP, and falls through to `launchPersistentContext(AUTH_DIR)`. That call fails with
a profile-lock error because the CDP Chrome process already holds
`~/.local/share/k3d-manager/profile/SingletonLock`. Node exits non-zero and
`acg_credentials_provision` prints the fallback.

---

## Reproduction

1. `make chrome-cdp` — starts CDP Chrome on port 9222
2. Leave it idle until all tabs close (or close them manually)
3. `make up` — fails with the INFO fallback

Confirm the state:
```bash
curl -s http://localhost:9222/json/list   # returns []
ps aux | grep "k3d-manager/profile"       # shows the Chrome PID
```

---

## Fix

### Change 1 — `playwright/acg_credentials.js`: add `http` import

**Exact old block (lines 1–4):**

```javascript
const { chromium } = require('playwright');
const fs = require('fs');
const os = require('os');
const path = require('path');
```

**Exact new block:**

```javascript
const { chromium } = require('playwright');
const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');
```

---

### Change 2 — `playwright/acg_credentials.js`: open blank tab when contexts is empty

**Exact old block (lines 185–188):**

```javascript
      if (!browserContext) {
        try { await _cdpBrowser.disconnect(); } catch {}
        _cdpBrowser = null;
      }
```

**Exact new block:**

```javascript
      if (!browserContext) {
        // Chrome has no open tabs — its default context is invisible to CDP until
        // a tab exists. Open a blank tab via the HTTP API to surface the profile
        // context; then re-query so Playwright can see it.
        console.error('INFO: CDP connected but no open contexts — opening blank tab to expose profile context.');
        try {
          await new Promise((resolve, reject) => {
            const req = http.request(
              { hostname: CDP_HOST, port: CDP_PORT, path: '/json/new', method: 'PUT' },
              res => { res.resume(); resolve(); }
            );
            req.on('error', reject);
            req.end();
          });
          await new Promise(r => setTimeout(r, 500));
          const _refreshedContexts = _cdpBrowser.contexts();
          if (_refreshedContexts.length > 0) {
            browserContext = _refreshedContexts[0];
            console.error('INFO: Default Chrome context now accessible after blank tab.');
          }
        } catch { /* fall through if blank tab fails */ }
        if (!browserContext) {
          try { await _cdpBrowser.disconnect(); } catch {}
          _cdpBrowser = null;
        }
      }
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_credentials.js` | Add `http` require; fix empty-contexts CDP fallthrough |

---

## Rules

- `node --check playwright/acg_credentials.js` — zero errors
- `shellcheck -S warning scripts/plugins/acg.sh scripts/lib/cdp.sh scripts/vars.sh` — zero new warnings
- Code change: `playwright/acg_credentials.js` only; memory-bank updates are also required (see DoD)

---

## Definition of Done

- [ ] `http` added to imports (line 3, after `fs`)
- [ ] `if (!browserContext)` block replaced with blank-tab logic
- [ ] `node --check playwright/acg_credentials.js` passes
- [ ] Committed and pushed to `fix/acg-credentials-cdp-empty-contexts`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(acg): open blank tab via HTTP API when CDP has no contexts
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT modify `acg.sh`, `cdp.sh`, or any file other than `playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `fix/acg-credentials-cdp-empty-contexts`
- Do NOT add a `setTimeout` longer than 500ms — Chrome registers the new target quickly
