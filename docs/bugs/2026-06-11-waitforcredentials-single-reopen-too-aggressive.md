# Bug: _waitForCredentials aborts after one reopen attempt — Azure panel needs more time

**Date:** 2026-06-11
**Branch (lib-acg):** `feat/v0.1.6`
**File:** `playwright/lib/sandbox.js`

---

## Symptom

```
WARN: Azure panel stayed closed after reopen attempt — aborting instead of looping for 420s.
ERROR: Azure panel stayed closed after reopen attempt — aborting instead of looping for 420s.
```

Azure sandbox IS running (visible text shows "Auto Shutdown at 11:07PM"), yet
`acg-credential-test` aborts extraction immediately after one reopen click.

---

## Root Cause

`_waitForCredentials` uses a boolean `reopenAttempted` flag. After clicking the reopen
button it waits only 3 seconds (`page.waitForTimeout(3000)`). On the very next loop
iteration `_findScopedButton` (with timeout=0) finds "Open Sandbox" still visible —
either because the Azure panel is still animating open, or the 3s render lag hasn't
resolved — and triggers the abort immediately because `reopenAttempted` is already `true`.

The prior fix for `2026-06-09-azure-provider-panel-closed-reopen-loop.md` correctly
stopped the infinite loop, but 3s + 1 attempt is too tight for a running Azure sandbox.

---

## Fix

### Change 1 — `playwright/lib/sandbox.js`: replace `reopenAttempted` boolean with `reopenCount` counter; increase reopen wait to 8s; allow 3 attempts

**Exact old block (line 204):**

```js
  let reopenAttempted = false;
```

**Exact new block:**

```js
  let reopenCount = 0;
```

---

**Exact old block (lines 258–266):**

```js
      if (reopenAttempted) {
        await _capturePageDebugState(page, providerLabel, `${providerLabel} panel stayed closed after reopen attempt — aborting instead of looping for 420s.`);
        throw new Error(`${providerLabel} panel stayed closed after reopen attempt — aborting instead of looping for 420s.`);
      }
      console.error(`INFO: ${providerLabel} panel closed — re-opening to retrieve credentials...`);
      await reopenBtn.click({ force: true }).catch(() => {});
      await page.waitForTimeout(3000);
      reopenAttempted = true;
      continue;
```

**Exact new block:**

```js
      if (reopenCount >= 3) {
        await _capturePageDebugState(page, providerLabel, `${providerLabel} panel stayed closed after ${reopenCount} reopen attempts — aborting.`);
        throw new Error(`${providerLabel} panel stayed closed after ${reopenCount} reopen attempts — aborting.`);
      }
      reopenCount++;
      console.error(`INFO: ${providerLabel} panel closed — re-opening to retrieve credentials (attempt ${reopenCount})...`);
      await reopenBtn.click({ force: true }).catch(() => {});
      await page.waitForTimeout(8000);
      continue;
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Replace `reopenAttempted` boolean with `reopenCount` counter; allow 3 attempts; increase post-reopen wait 3s → 8s |

---

## Rules

- `node --check playwright/lib/sandbox.js` — must pass
- No other files touched

---

## Before You Start

- Repo: `lib-acg`
- Branch: `feat/v0.1.6`
- Run: `git pull origin feat/v0.1.6`
- Read: `playwright/lib/sandbox.js` in full
- Confirm line 204 is `let reopenAttempted = false;` and lines 258–266 match the exact old block above before editing

---

## Definition of Done

- [ ] `let reopenAttempted = false;` replaced with `let reopenCount = 0;`
- [ ] Abort condition changed from `if (reopenAttempted)` to `if (reopenCount >= 3)`
- [ ] Abort error message uses `${reopenCount}` count
- [ ] `reopenAttempted = true;` replaced with `reopenCount++;`
- [ ] `console.error` message includes `(attempt ${reopenCount})`
- [ ] `page.waitForTimeout(3000)` changed to `page.waitForTimeout(8000)`
- [ ] `node --check playwright/lib/sandbox.js` passes
- [ ] No files other than `playwright/lib/sandbox.js` touched
- [ ] Committed and pushed to `feat/v0.1.6`
- [ ] memory-bank in k3d-manager updated with lib-acg commit SHA and task status

**Commit message (exact):**
```
fix(sandbox): allow 3 reopen attempts with 8s wait — single 3s attempt too tight for Azure panel render
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/lib/sandbox.js`
- Do NOT commit to `main` — work on `feat/v0.1.6` in lib-acg
- Do NOT change the abort threshold above 3 — this is a render timing fix, not a retry loop
