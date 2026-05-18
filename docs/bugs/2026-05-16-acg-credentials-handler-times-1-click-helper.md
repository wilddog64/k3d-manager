# Bug: acg_credentials — addLocatorHandler loops 3× then times out; Start Sandbox button outside viewport

**Branch:** `k3d-manager-v1.4.6`
**File:** `scripts/lib/acg/playwright/acg_credentials.js`

---

## Problem

Two related failures visible in the same run:

**Failure 1 — handler loops:**
```
INFO: [handler] Clicking "Extend Session" to extend sandbox...
INFO: [handler] Clicking "Extend Session" to extend sandbox...
INFO: [handler] Clicking "Extend Session" to extend sandbox...
ERROR: locator.click: Timeout 30000ms exceeded.
  3 × found locator('[role="dialog"][data-open="true"]:has-text("Extend Your Session")'),
      intercepting action to run the handler
    - locator handler has finished, waiting for locator to be hidden
    - interception handler has finished, continuing
    - element was detached from the DOM, retrying       ← page re-renders after dialog dismiss
      - found locator('[role="dialog"][data-open="true"]...'), intercepting action to run the handler
```

**Root cause 1:** `addLocatorHandler` has no `times` limit. After the handler dismisses the dialog, the Pluralsight SPA re-renders the layout (Start Sandbox button detaches and re-attaches). During that re-render, `[data-open="true"]` briefly flickers back on the dialog, triggering the handler again. Three cycles exhaust the 30s click budget.

**Failure 2 — button outside viewport:**
```
- done scrolling
- element is outside of the viewport
```

**Root cause 2:** After the dialog is dismissed, the page layout shifts and the Start Sandbox button is no longer in the viewport. Plain `.click()` waits for the element to be in the viewport and actionable, which it never is after the re-render, so it times out.

---

## Reproduction

1. Run `make up` with an AWS sandbox session that has "Extend Your Session" prompt
2. Handler fires, dialog closes, page re-renders → handler fires 2 more times → 30s timeout

---

## Fix

### Change 1 — Add `{ times: 1 }` and increase settle to 1000ms in `addLocatorHandler`

**Exact old block (lines 252–267):**

```javascript
    // Intercept "Extend Your Session" dialog if it appears mid-click — fires at most once per session
    await page.addLocatorHandler(
      page.locator('[role="dialog"][data-open="true"]:has-text("Extend Your Session")'),
      async () => {
        console.error('INFO: [handler] Clicking "Extend Session" to extend sandbox...');
        const _extendBtn = page.locator('[role="dialog"]:has-text("Extend Your Session") button:has-text("Extend Session")').first();
        if (await _extendBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
          await _extendBtn.click({ force: true }).catch(() => {});
          await page.waitForTimeout(500).catch(() => {});
          await page.keyboard.press('Escape').catch(() => {});
        } else {
          await page.keyboard.press('Escape').catch(() => {});
        }
        await page.waitForTimeout(250).catch(() => {});
      }
    );
```

**Exact new block:**

```javascript
    // Intercept "Extend Your Session" dialog if it appears mid-click — fires at most once per session
    await page.addLocatorHandler(
      page.locator('[role="dialog"][data-open="true"]:has-text("Extend Your Session")'),
      async () => {
        console.error('INFO: [handler] Clicking "Extend Session" to extend sandbox...');
        const _extendBtn = page.locator('[role="dialog"]:has-text("Extend Your Session") button:has-text("Extend Session")').first();
        if (await _extendBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
          await _extendBtn.click({ force: true }).catch(() => {});
          await page.waitForTimeout(500).catch(() => {});
          await page.keyboard.press('Escape').catch(() => {});
        } else {
          await page.keyboard.press('Escape').catch(() => {});
        }
        await page.waitForTimeout(1000).catch(() => {});
      },
      { times: 1 }
    );
```

**Why:**
- `{ times: 1 }` caps handler invocations to exactly one. After the first fire, any subsequent `data-open` flicker from page re-render is not intercepted — Playwright retries the click normally.
- `waitForTimeout(250)` → `waitForTimeout(1000)`: longer settle gives the SPA time to finish its re-render before Playwright resumes the click, reducing the chance that the button is still in a transitional position.

---

### Change 2 — Add `_clickStartSandbox` helper before `extractCredentials`

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
  await buttonLocator.scrollIntoViewIfNeeded().catch(() => {});
  await buttonLocator.click({ force: true });
}

async function extractCredentials() {
```

**Why:**
- `waitFor({ state: 'hidden' })` waits up to 3000ms for the dialog to fully disappear before attempting the click — catches any residual re-render artifact the handler may have left behind.
- `scrollIntoViewIfNeeded()` ensures the button is scrolled as close to viewport as possible.
- `{ force: true }` dispatches the click directly to the element (bypassing viewport and overlay actionability checks) so the Start Sandbox button is clicked even if the page layout hasn't fully settled.

---

### Change 3a — Replace `startButton.click()` with `_clickStartSandbox`

**Exact old block (lines 497–498):**

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

### Change 3b — Replace `startButton2.click()` with `_clickStartSandbox`

**Exact old block (lines 535–536):**

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
| `scripts/lib/acg/playwright/acg_credentials.js` | Add `{ times: 1 }` + 1000ms settle to handler (Change 1); add `_clickStartSandbox` helper (Change 2); replace both Start Sandbox `.click()` calls with the helper (Changes 3a, 3b) |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass (zero syntax errors)
- No other files touched

---

## Definition of Done

**Change 1 — handler options:**
- [ ] `{ times: 1 }` added as third argument to `addLocatorHandler`
- [ ] `waitForTimeout(250)` changed to `waitForTimeout(1000)` inside the handler
- [ ] All other handler lines unchanged (selector, log, `isVisible` timeout 3000, click, 500ms, Escape, fallback Escape)

**Change 2 — helper function:**
- [ ] `_clickStartSandbox(page, buttonLocator)` added as a module-level `async function` immediately before `async function extractCredentials()`
- [ ] Helper body: `waitFor({ state: 'hidden', timeout: 3000 })` (with catch), `scrollIntoViewIfNeeded()` (with catch), `click({ force: true })` (no catch — propagates on failure)

**Change 3 — click sites:**
- [ ] `await startButton.click()` replaced with `await _clickStartSandbox(page, startButton)` (line ~498)
- [ ] `await startButton2.click()` replaced with `await _clickStartSandbox(page, startButton2)` (line ~536)
- [ ] `openButton.click()`, `resumeButton.click()` — NOT changed

**All changes:**
- [ ] No other lines touched
- [ ] `node --check scripts/lib/acg/playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Commit message (exact): `fix(acg-credentials): times:1 handler + _clickStartSandbox force-click to prevent loop and viewport miss`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/acg/playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT use `button:has-text("Extend")` — full exact label is `"Extend Session"`
- Do NOT use `button.pando-button--usage_filled` — previously matched the wrong element
- Do NOT use `timeout: 1000` for `isVisible` — modal animation requires 3000ms
- Do NOT change the proactive inline dismiss blocks BEFORE the start flow (lines ~367–400) — Escape-only and intentionally unchanged
- Do NOT change the `_waitForCredentials` inline dismiss (Change 2 from the previous spec) — already correctly uses `button:has-text("Extend Session")` with 3000ms
- Do NOT change `openButton.click()` or `resumeButton.click()` — not affected by this issue
- Do NOT add `.first()` inside `_clickStartSandbox` — `startButton` and `startButton2` are already `.first()` locators
