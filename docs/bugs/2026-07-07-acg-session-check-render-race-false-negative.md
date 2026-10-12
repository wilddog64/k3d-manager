# Bugfix: v0.4.3 — ACG session check false-negatives on a slow-rendering sandbox page

**Branch:** `feat/v0.4.3`
**Repo:** `lib-foundation` (standalone — NOT the k3d-manager subtree copy)
**Files:**
- `scripts/lib/acg/playwright/lib/pluralsight_login.js`
- `scripts/lib/acg/acg_session_check.js`
- `scripts/lib/acg/tests/providers/pluralsight_login.test.js`
- `scripts/lib/acg/tests/providers/acg_session_check.test.js`

---

## Problem

`acg-up` reuses an existing CDP browser that is **already signed in to Pluralsight**, yet the
session gate still drops to the interactive prompt:

```
INFO: [acg] Reusing existing CDP browser on :9222
INFO: Checking Pluralsight (ACG) session in Antigravity browser...
ACTION REQUIRED: Please log into Pluralsight in the browser, then wait for the signin page to clear.
```

Diagnosed live: tab 0 was already at `SANDBOX_URL` and logged in (a second `/library/` tab
confirmed the session). Probing the six `LOGGED_IN_SELECTORS` against that same live page a
few moments later showed **`text=/Cloud Sandboxes/i` and `text=/Open Sandbox/i` VISIBLE** — so
the selectors are correct and the session is valid. The failure was **transient**.

**Root cause:** a render-timing race in the initial session probe.
`acg_session_check.js` navigates with `waitUntil: 'domcontentloaded'` (which fires before the
sandbox SPA paints), swallows any nav timeout with `.catch(() => {})`, and then calls
`pageLooksLoggedIn(page)` — which is a **single-shot** check allowing only 1.5 s per selector
with no retry. If the SPA has not painted the "Cloud Sandboxes" / "Open Sandbox" text within
that window, all six selectors miss and the gate declares the user logged-out. Because
`ACG_USERNAME`/`ACG_PASSWORD` were unset, headless auto-login was skipped and the run fell
straight through to the manual `ACTION REQUIRED` prompt.

This fix hardens the detector so a slow render no longer produces a false negative. It does
**not** change selectors (they are correct) and does **not** touch the credential/auto-login
gating.

---

## Reproduction

Connect to a CDP browser that is signed in to Pluralsight but where the sandbox SPA is still
painting when the probe runs (e.g. immediately after a cold tab navigation). The current
single-shot `pageLooksLoggedIn` returns `false` and the gate prompts for login even though the
session is valid. See the jest regression test below for a deterministic reproduction.

---

## Fix

### Change 1 — `scripts/lib/acg/playwright/lib/pluralsight_login.js`: retry the logged-in probe

Make `pageLooksLoggedIn` retry across a short settle window. Backward-compatible: with no
options it behaves exactly as today (single attempt, 1.5 s per selector) so existing callers
are unchanged.

**Exact old block (lines 33–35):**

```javascript
async function pageLooksLoggedIn(page) {
  return anyVisible(page, LOGGED_IN_SELECTORS, 1500);
}
```

**Exact new block:**

```javascript
async function pageLooksLoggedIn(page, options) {
  const { attempts = 1, perSelectorTimeoutMs = 1500, settleMs = 1000 } = options || {};
  for (let i = 0; i < attempts; i += 1) {
    if (await anyVisible(page, LOGGED_IN_SELECTORS, perSelectorTimeoutMs)) {
      return true;
    }
    if (i < attempts - 1) {
      await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
      await page.waitForTimeout(settleMs);
    }
  }
  return false;
}
```

### Change 2 — `scripts/lib/acg/acg_session_check.js`: settle after nav + retry the initial probe

Two edits in `_main`.

**Exact old block (lines 48–52):**

```javascript
    await page.goto(SANDBOX_URL, { waitUntil: 'domcontentloaded', timeout: 30000 }).catch(() => {});
    if (await pageLooksLoggedIn(page)) {
      process.stdout.write('ACG_SESSION_OK\n');
      return;
    }
```

**Exact new block:**

```javascript
    const navigatedToSandbox = await page.goto(SANDBOX_URL, { waitUntil: 'domcontentloaded', timeout: 30000 })
      .then(() => true)
      .catch((err) => {
        console.error(`INFO: sandbox navigation issue (will still probe session): ${err.message}`);
        return false;
      });
    if (navigatedToSandbox) {
      await page.waitForLoadState('networkidle', { timeout: 8000 }).catch(() => {});
    }
    if (await pageLooksLoggedIn(page, { attempts: 4 })) {
      process.stdout.write('ACG_SESSION_OK\n');
      return;
    }
```

Also harden the post-auto-login re-check against the same race.

**Exact old block (line 60):**

```javascript
      if (loginOk && await pageLooksLoggedIn(page)) {
```

**Exact new block:**

```javascript
      if (loginOk && await pageLooksLoggedIn(page, { attempts: 3 })) {
```

### Change 3 — `scripts/lib/acg/tests/providers/pluralsight_login.test.js`: regression test

Prove that a single attempt misses a slow-rendering logged-in page (the bug) and that retrying
detects it (the fix).

**Exact old block (line 1):**

```javascript
const { loginWithPage } = require('../../playwright/lib/pluralsight_login');
```

**Exact new block:**

```javascript
const { loginWithPage, pageLooksLoggedIn } = require('../../playwright/lib/pluralsight_login');
```

**Append at end of file (after the final `});`):**

```javascript

function makeSlowRenderPage({ loggedInVisibleFromAttempt = 1 } = {}) {
  let renderAttempt = 0;
  const locators = new Map();
  return {
    goto: jest.fn().mockResolvedValue(undefined),
    locator: jest.fn((selector) => {
      const isLoggedInSelector = selector.includes('Cloud Sandboxes') || selector.includes('Open Sandbox');
      if (!locators.has(selector)) {
        locators.set(selector, {
          first: jest.fn().mockReturnThis(),
          isVisible: jest.fn(async () => isLoggedInSelector && renderAttempt >= loggedInVisibleFromAttempt),
        });
      }
      return locators.get(selector);
    }),
    url: jest.fn(() => 'https://app.pluralsight.com/hands-on/playground/cloud-sandboxes'),
    waitForLoadState: jest.fn(async () => { renderAttempt += 1; }),
    waitForTimeout: jest.fn().mockResolvedValue(undefined),
  };
}

describe('pageLooksLoggedIn render-race hardening', () => {
  test('single attempt misses a slow-rendering logged-in page (reproduces the false negative)', async () => {
    const page = makeSlowRenderPage({ loggedInVisibleFromAttempt: 1 });
    const result = await pageLooksLoggedIn(page, { attempts: 1, settleMs: 0 });
    expect(result).toBe(false);
  });

  test('retrying across settle waits detects the logged-in page once it renders', async () => {
    const page = makeSlowRenderPage({ loggedInVisibleFromAttempt: 1 });
    const result = await pageLooksLoggedIn(page, { attempts: 4, settleMs: 0 });
    expect(result).toBe(true);
    expect(page.waitForLoadState).toHaveBeenCalled();
  });
});
```

### Change 4 — `scripts/lib/acg/tests/providers/acg_session_check.test.js`: add `waitForLoadState` to the mock page

`_main` now calls `page.waitForLoadState('networkidle', …)` after a successful nav. The
existing `makePage()` mock lacks that method, so the call throws `TypeError` synchronously
(before the `.catch(() => {})` can attach) and both existing tests crash. Add the missing
method. `pageLooksLoggedIn` is mocked in this file, so the retry loop never runs here — only
`_main`'s single `waitForLoadState` call needs to resolve.

**Exact old block (lines 18–27):**

```javascript
function makePage() {
  let currentUrl = 'https://signin.example';
  return {
    goto: jest.fn(async (url) => {
      currentUrl = url;
    }),
    url: jest.fn(() => currentUrl),
    waitForTimeout: jest.fn().mockResolvedValue(undefined),
  };
}
```

**Exact new block:**

```javascript
function makePage() {
  let currentUrl = 'https://signin.example';
  return {
    goto: jest.fn(async (url) => {
      currentUrl = url;
    }),
    url: jest.fn(() => currentUrl),
    waitForLoadState: jest.fn().mockResolvedValue(undefined),
    waitForTimeout: jest.fn().mockResolvedValue(undefined),
  };
}
```

The existing two assertions still hold: `page.waitForTimeout` is still never called on the
no-creds / MFA-required paths (the real retry loop is mocked out), and both paths still reject
with `ACG_SESSION_EXPIRED`.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/playwright/lib/pluralsight_login.js` | `pageLooksLoggedIn` retries across a settle window (backward-compatible via optional `attempts`) |
| `scripts/lib/acg/acg_session_check.js` | Initial probe waits for `networkidle` + retries; nav failure logged not swallowed; post-login re-check retries |
| `scripts/lib/acg/tests/providers/pluralsight_login.test.js` | Regression test: single-shot false-negative vs. retry success |
| `scripts/lib/acg/tests/providers/acg_session_check.test.js` | Add `waitForLoadState` to the mock page so `_main`'s new `networkidle` settle does not crash the existing tests |

---

## Rules

- `node --check scripts/lib/acg/acg_session_check.js` — must pass (NOTE: `npm run check` does
  NOT cover this file; run it explicitly)
- `npm run check` — must pass (covers `playwright/**/*.js`)
- `npm test` — jest green, all existing + 2 new tests pass (the `acg_session_check.test.js` mock fix keeps its 2 existing tests green)
- Do NOT change any selector in `LOGGED_IN_SELECTORS` — they are correct
- Do NOT change credential/auto-login gating or the `ACG_SESSION_EXPIRED` non-interactive path
- No other files touched
- Run jest/node from `scripts/lib/acg/` (that is where `package.json` and `node_modules` live)

---

## Definition of Done

- [ ] `pageLooksLoggedIn` accepts `{ attempts, perSelectorTimeoutMs, settleMs }`, defaults preserve single-shot behavior
- [ ] `acg_session_check.js` initial probe uses `{ attempts: 4 }` after a `networkidle` settle; nav failure is logged, not silently swallowed
- [ ] Regression proof: the new `attempts: 4` test **fails** on the old single-shot `pageLooksLoggedIn` (options ignored → `false`), and **passes** on the fix
- [ ] `node --check scripts/lib/acg/acg_session_check.js` — OK
- [ ] `npm run check` — OK
- [ ] `npm test` — all pass
- [ ] Committed and pushed to `feat/v0.4.3`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg): retry logged-in detection to stop session-check render-race false negative
```

---

## Follow-up (NOT part of this task)

After this merges and lib-foundation is tagged, the fix must be pulled into k3d-manager via
`git subtree pull --prefix=scripts/lib/foundation`. That is a separate step in k3d-manager —
do NOT touch the k3d-manager subtree copy here.

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the four listed targets
- Do NOT edit the k3d-manager subtree copy at `scripts/lib/foundation/` — work only in the standalone lib-foundation repo
- Do NOT commit to `main` — work on `feat/v0.4.3`
