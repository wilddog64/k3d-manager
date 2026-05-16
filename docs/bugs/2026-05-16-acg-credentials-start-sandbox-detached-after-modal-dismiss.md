# Bug: acg_credentials — Start Sandbox button detaches after modal dismiss (off-viewport + React re-render)

**Branch:** `k3d-manager-v1.4.6`
**File:** `scripts/lib/acg/playwright/acg_credentials.js`

---

## Problem

After the "Extend Your Session" handler dismisses the dialog, the page re-renders. The Start
Sandbox button moves outside the viewport and React replaces its DOM node before Playwright
can complete the click. The original locator handle is stale; Playwright retries against the
detached node until the 30s timeout expires.

```
- element is visible, enabled and stable
- scrolling into view if needed
- element is outside of the viewport
- element is not stable
- element was detached from the DOM, retrying
```

**Root cause:** `startButton.click()` and `startButton2.click()` resume on the original locator
handle after the handler returns. The post-dismissal React re-render moves the button off-screen
and replaces its DOM node. The fix is to re-scroll and use `{ force: true }` so the click lands
on the current DOM node without Playwright's stability gate blocking it.

---

## Reproduction

1. Have an AWS sandbox session near expiry
2. Run `make up`
3. "Extend Your Session" dialog appears during Start Sandbox (Step 2)
4. Handler dismisses the dialog successfully
5. Page re-renders — button detaches — 30s timeout hit

---

## Fix

### Change 1 — Add `_clickStartSandbox` helper before `extractCredentials`

**Exact old block (lines 150–152):**

```javascript
}

async function extractCredentials() {
```

**Exact new block:**

```javascript
}

async function _clickStartSandbox(page, buttonLocator) {
  const _prompt = page.locator('[role="dialog"]:has-text("Extend Your Session")').first();
  await _prompt.waitFor({ state: 'hidden', timeout: 3000 }).catch(() => {});
  const _btn = buttonLocator.first();
  await _btn.scrollIntoViewIfNeeded().catch(() => {});
  await _btn.click({ force: true });
}

async function extractCredentials() {
```

**Why:** `waitFor({ state: 'hidden', timeout: 3000 })` is a safety net (dialog already gone
at this call site — exits instantly). `scrollIntoViewIfNeeded()` corrects the viewport shift
caused by the dialog dismissal. `{ force: true }` bypasses Playwright's stability gate so the
click lands on the current DOM node even during a brief React re-render cycle.

---

### Change 2 — Replace `startButton.click()` with helper call

**Exact old block:**

```javascript
          console.error('INFO: Clicking Start Sandbox...');
          await startButton.click();
```

**Exact new block:**

```javascript
          console.error('INFO: Clicking Start Sandbox...');
          await _clickStartSandbox(page, startButton);
```

---

### Change 3 — Replace `startButton2.click()` with helper call

**Exact old block:**

```javascript
          console.error('INFO: Clicking Start Sandbox (Step 2)...');
          await startButton2.click();
```

**Exact new block:**

```javascript
          console.error('INFO: Clicking Start Sandbox (Step 2)...');
          await _clickStartSandbox(page, startButton2);
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/playwright/acg_credentials.js` | Add `_clickStartSandbox` helper; replace both `startButton.click()` calls |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass (zero syntax errors)
- No other files touched

---

## Definition of Done

- [ ] `_clickStartSandbox(page, buttonLocator)` function is present before `extractCredentials`
- [ ] `_prompt.waitFor({ state: 'hidden', timeout: 3000 }).catch(() => {})` is in the helper
- [ ] `_btn.scrollIntoViewIfNeeded().catch(() => {})` is in the helper
- [ ] `_btn.click({ force: true })` is the last line of the helper
- [ ] `startButton.click()` replaced with `_clickStartSandbox(page, startButton)` (Change 2)
- [ ] `startButton2.click()` replaced with `_clickStartSandbox(page, startButton2)` (Change 3)
- [ ] No other lines touched
- [ ] `node --check scripts/lib/acg/playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Commit message (exact): `fix(acg-credentials): re-scroll and force-click Start Sandbox after modal dismiss`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/acg/playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT remove `{ force: true }` — it is required to bypass Playwright's stability gate during React re-render
- Do NOT remove `scrollIntoViewIfNeeded()` — the button is off-viewport after modal dismissal
- Do NOT inline the helper at only one call site — both `startButton` and `startButton2` need it
