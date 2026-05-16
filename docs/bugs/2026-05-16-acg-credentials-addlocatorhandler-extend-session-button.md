# Bug: acg_credentials — "Extend Your Session" handler used wrong button label; re-add with exact text

**Branch:** `k3d-manager-v1.4.6`
**File:** `scripts/lib/acg/playwright/acg_credentials.js`

---

## Problem

The `addLocatorHandler` was removed in `02d792a4` because no selector could reliably click the
Extend button. Visual inspection of the live dialog revealed the exact button text:

- **"Cancel"** — outlined secondary button (dismisses without extending)
- **"Extend Session"** — filled purple primary button (extends by 4 hours)

Previous attempts used `button:has-text("Extend")` (substring of "Extend Session" — should have
matched but did NOT, likely because `isVisible({ timeout: 1000 })` timed out while the modal was
still animating in) and `button.pando-button--usage_filled` (matched Cancel or another element
instead). With `addLocatorHandler` removed, the dialog now blocks `startButton2.click()` for the
full 30s and times out with no action taken.

**Root cause:** Previous handler used wrong/ambiguous selectors. Fix is to re-add
`addLocatorHandler` with the exact label `button:has-text("Extend Session")` and a 3000ms
`isVisible` timeout to survive the modal animation.

---

## Reproduction

1. Have an AWS sandbox session near expiry
2. Run `make up`
3. "Extend Your Session" dialog appears during Start Sandbox (Step 2)
4. No handler — `startButton2.click()` retries for 30s, dialog blocks it, timeout hit

---

## Fix

### Change 1 — Re-add `addLocatorHandler` with exact "Extend Session" button text

**Exact old block (lines 251–252, current state after removal):**

```javascript

    // Skip navigation entirely if sandbox panel is already loaded on the current page
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
        await page.waitForTimeout(250).catch(() => {});
      }
    );

    // Skip navigation entirely if sandbox panel is already loaded on the current page
```

**Why:**
- `button:has-text("Extend Session")` is the exact label confirmed from live dialog screenshot.
- `timeout: 3000` on `isVisible` gives the modal animation enough time to complete before the
  button check fires (previous `timeout: 1000` caused false-negative → Escape fallback).
- Clicking "Extend Session" extends the sandbox by 4 hours. Per the dialog: "This can only be
  done once per session" — so the handler will fire at most once; the dialog will not reappear
  after a successful extension.
- 500ms + Escape dismisses the "Session extended" confirmation modal.
- 250ms settle before returning lets the page stabilize before Playwright resumes the click.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/playwright/acg_credentials.js` | Re-add `addLocatorHandler` with exact `button:has-text("Extend Session")` selector and 3000ms visibility timeout |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass (zero syntax errors)
- No other files touched

---

## Definition of Done

- [ ] `addLocatorHandler` block is present (re-added at the same location it was removed from)
- [ ] Registered locator: `page.locator('[role="dialog"][data-open="true"]:has-text("Extend Your Session")')`
- [ ] Handler log: `'INFO: [handler] Clicking "Extend Session" to extend sandbox...'`
- [ ] Extend button selector: `'[role="dialog"]:has-text("Extend Your Session") button:has-text("Extend Session")'`
- [ ] `isVisible` timeout is `3000` (not 1000)
- [ ] After click: `waitForTimeout(500)` then `page.keyboard.press('Escape')`
- [ ] Fallback when button not visible: `page.keyboard.press('Escape')`
- [ ] Final settle: `waitForTimeout(250)` before closing the handler
- [ ] No other lines touched
- [ ] `node --check scripts/lib/acg/playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Commit message (exact): `fix(acg-credentials): re-add addLocatorHandler with exact "Extend Session" button label`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/acg/playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT use `button:has-text("Extend")` — ambiguous; use the full exact label "Extend Session"
- Do NOT use `button.pando-button--usage_filled` — previously matched the wrong button
- Do NOT use `timeout: 1000` for `isVisible` — the modal animation takes longer; use 3000
- Do NOT remove the `button:has-text("Cancel")` inline dismiss blocks elsewhere in the file — those are separate proactive checks and must stay
