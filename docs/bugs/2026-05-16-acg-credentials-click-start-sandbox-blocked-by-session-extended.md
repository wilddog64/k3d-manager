# Bug: acg-credentials — _clickStartSandbox times out — "Session extended" modal blocks Start Sandbox button

**Branch:** `k3d-manager-v1.4.6`
**Files:** `scripts/lib/acg/playwright/acg_credentials.js`

---

## Problem

`_clickStartSandbox` times out with:

```
ERROR: locator.click: Timeout 30000ms exceeded.
Call log:
  - waiting for locator('button:has-text("Start Sandbox")').first()
```

The "Start Sandbox" button passes `isVisible()` but then the click itself times out because
the "Session extended" / "Your sandbox has been extended." modal appears (from the
`acg_extend_playwright` pre-flight step) and React unmounts or hides the Start Sandbox
button while the modal is active. By the time `_clickStartSandbox` reaches `buttonLocator.click()`,
the button is no longer in the DOM.

**Root cause:** `_clickStartSandbox` only waits for "Extend Your Session" to close before
clicking. It does not check for the "Session extended" confirmation card, which can appear
at the same time and block the page.

**Fix:** Add a dismissal of the "Session extended" card inside `_clickStartSandbox`, between
the "Extend Your Session" wait and the scroll + click. This ensures the page is clear of
any extension-related overlays before the Start Sandbox click is attempted.

---

## Reproduction

1. Run `make up` — `acg_extend_playwright` pre-flight runs and extends the session
2. "Session extended" / "Your sandbox has been extended." modal appears on the page
3. `acg_credentials.js` starts — navigates to sandbox page with modal still visible
4. `startButton.isVisible()` returns true (button is in DOM even with modal covering it)
5. `_clickStartSandbox` waits for "Extend Your Session" to hide (3s) — not present, proceeds
6. Does NOT wait for "Session extended" card to hide
7. `buttonLocator.click({ force: true })` — React has unmounted the button → 30s timeout

---

## Fix

### Change 1 — `acg_credentials.js` lines 152–157: add "Session extended" dismissal in `_clickStartSandbox`

**Exact old block:**
```javascript
async function _clickStartSandbox(page, buttonLocator) {
  const _prompt = page.locator('[role="dialog"]:has-text("Extend Your Session")').first();
  await _prompt.waitFor({ state: 'hidden', timeout: 3000 }).catch(() => {});
  await buttonLocator.scrollIntoViewIfNeeded().catch(() => {});
  await buttonLocator.click({ force: true });
}
```

**Exact new block:**
```javascript
async function _clickStartSandbox(page, buttonLocator) {
  const _prompt = page.locator('[role="dialog"]:has-text("Extend Your Session")').first();
  await _prompt.waitFor({ state: 'hidden', timeout: 3000 }).catch(() => {});
  const _sessionExtended = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
  if (await _sessionExtended.isVisible({ timeout: 2000 }).catch(() => false)) {
    await _sessionExtended.locator('button').first().click({ force: true }).catch(() => {});
    await _sessionExtended.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
  }
  await buttonLocator.scrollIntoViewIfNeeded().catch(() => {});
  await buttonLocator.click({ force: true });
}
```

**Why:** The "Session extended" card uses the same locator pattern already proven correct
by `8eb6fd02`. Inserting the dismissal inside `_clickStartSandbox` ensures the card is
gone before the scroll + click, so React has restored the Start Sandbox button to the DOM.
All existing callers of `_clickStartSandbox` inherit the fix.

---

## Files Changed

| File | Changes |
|------|---------|
| `scripts/lib/acg/playwright/acg_credentials.js` | Change 1 — insert 4 lines into `_clickStartSandbox` between the "Extend Your Session" wait and the scroll |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass
- No other files touched
- Only `_clickStartSandbox` (lines 152–157) changes — all callers and all other functions unchanged

---

## Definition of Done

- [ ] `_clickStartSandbox` body is exactly the new 9-line block above
- [ ] No other functions modified
- [ ] `node --check scripts/lib/acg/playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Committed to `k3d-manager-v1.4.6`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

**Commit message (exact):**
```
fix(acg-credentials): dismiss Session extended modal in _clickStartSandbox before clicking Start Sandbox
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/acg/playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT change the callers of `_clickStartSandbox` — the fix is inside the function only
- Do NOT change `extractCredentials()` Pattern 1, 2, or 3 blocks
- Do NOT change `_waitForCredentials()` or `addLocatorHandler`
- Do NOT change the line count or body of any function other than `_clickStartSandbox`
