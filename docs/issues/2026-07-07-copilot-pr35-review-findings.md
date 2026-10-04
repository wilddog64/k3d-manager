# Copilot PR #35 Review Findings — v0.4.3 ACG session-check render-race fix

**PR:** [#35](https://github.com/wilddog64/lib-foundation/pull/35) — `fix(acg): retry logged-in detection to stop session-check render-race false negative`
**Branch:** `feat/v0.4.3`
**Reviewer:** `copilot-pull-request-reviewer[bot]`
**Date:** 2026-07-07

Copilot raised 4 review threads. Three were the same underlying timing concern (fixed by
`487b2f9`); one was a robustness observation resolved by design.

---

## Finding 1 (+3, +4) — `pageLooksLoggedIn` retries could balloon into a tens-of-seconds probe

**Where:**
- `scripts/lib/acg/playwright/lib/pluralsight_login.js:53` — the `anyVisible` loop
- `scripts/lib/acg/acg_session_check.js:57` — the `{ attempts: 4 }` initial probe
- `scripts/lib/acg/acg_session_check.js:68` — the `{ attempts: 3 }` post-auto-login re-check

**What Copilot flagged:** `anyVisible` checked the 6 `LOGGED_IN_SELECTORS` **sequentially**,
each with `perSelectorTimeoutMs` (default 1500 ms). On a genuinely logged-out page (all
selectors miss) a single attempt costs `6 × 1.5s ≈ 9s`, so `{ attempts: 4 }` plus the
`networkidle`/`settleMs` waits between attempts could balloon to tens of seconds before the
gate could fail-fast or prompt interactively. Copilot suggested running the visibility checks
in parallel so each attempt is bounded by `perSelectorTimeoutMs` rather than
`selectors.length × perSelectorTimeoutMs`.

**Fix applied (`487b2f9`):** parallelized `anyVisible` with early-return semantics.

Before:
```javascript
async function anyVisible(page, selectors, timeoutMs) {
  for (const selector of selectors) {
    const locator = page.locator(selector).first();
    if (await locator.isVisible({ timeout: timeoutMs }).catch(() => false)) {
      return true;
    }
  }
  return false;
}
```

After:
```javascript
async function anyVisible(page, selectors, timeoutMs) {
  const checks = selectors.map((selector) =>
    page.locator(selector).first().isVisible({ timeout: timeoutMs }).catch(() => false),
  );
  if (checks.length === 0) {
    return false;
  }
  return new Promise((resolve) => {
    let pending = checks.length;
    for (const check of checks) {
      check.then((visible) => {
        if (visible) {
          resolve(true);
        } else if ((pending -= 1) === 0) {
          resolve(false);
        }
      });
    }
  });
}
```

All selector checks now run concurrently; the function resolves `true` on the **first**
visible selector (fast logged-in happy path unchanged) and `false` only once all have
resolved. Each attempt is bounded by a single `perSelectorTimeoutMs` (~1.5s), so the
`{ attempts: 4 }` worst case drops from tens of seconds to a few seconds. Both `pageLooksLoggedIn`
call sites benefit; the shared retry defaults were kept so the two probes stay consistent.

**Root cause:** the retry hardening (adding `attempts`) multiplied an already-sequential
per-selector timeout. The original single-shot probe masked the sequential cost because it ran
only once.

---

## Finding 2 — `.catch()` cannot suppress a synchronous `TypeError` from a missing Page method

**Where:** `scripts/lib/acg/playwright/lib/pluralsight_login.js:53` —
`await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {})`

**What Copilot flagged:** `.catch()` only handles a **rejected** promise. If a test/mock `Page`
lacks `waitForLoadState`, calling `page.waitForLoadState(...)` throws `TypeError` synchronously,
before `.catch` can attach.

**Resolution — by design, no code change.** In production a real Playwright `Page` always
exposes `waitForLoadState`/`waitForTimeout`, so this cannot throw at runtime. The only place it
bit us was a **test double**: the existing `acg_session_check.test.js` mock lacked the method,
which crashed the two existing tests when `_main` gained its `networkidle` settle. That was
fixed in this PR by `d803a00` (spec Change 4) — `makePage()` now provides
`waitForLoadState`/`waitForTimeout`. We deliberately do **not** add a
`typeof page.waitForLoadState === 'function'` guard around the production call: it would mask
genuine Page-contract violations and force the same guard across every optional Page method.
Test doubles own the contract.

---

## Process Note

The Change-4 blocker (a mock lacking a newly-called Page method) and Copilot Finding 2 are the
same class of issue surfacing from two directions. Template rule to carry forward: **when a
spec adds a call to an optional Playwright `Page` method inside a helper, the spec's file list
must include every test double that constructs a fake `Page` for that helper's call graph —
not just the helper's own test file.** The v0.4.3 spec originally listed only
`pluralsight_login.test.js`; `acg_session_check.test.js` also drives `_main` and needed the
mock update (Change 4, added during review).
