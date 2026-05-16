# Bug: acg_credentials — "Extend Your Session" Cancel dismiss causes session expiry + 420s credential timeout

**Branch:** `k3d-manager-v1.4.6`
**File:** `scripts/lib/acg/playwright/acg_credentials.js`

---

## Problem

Two places in the file dismiss the "Extend Your Session" dialog with `Cancel` instead of
`Extend Session`. Cancel does not extend the sandbox — the session continues expiring. This
causes two distinct failure modes:

**Failure 1 — during `startButton2.click()`:** The `addLocatorHandler` was removed (`02d792a4`)
because the Extend button selector was unknown. Without the handler, if the dialog appears
mid-click, the click blocks until 30s timeout.

**Failure 2 — during `_waitForCredentials` (420s timeout):** The inline dismiss in the 420s
credential wait loop (lines 437-446) clicks `button:has-text("Cancel")`. If the dialog appears
during the wait and Cancel is clicked, the session is not extended. The sandbox session then
expires during the wait, the sandbox terminates, credential inputs never populate, and the
420s timer exhausts.

```
INFO: Clicking Start Sandbox (Step 2)...
INFO: Waiting for credentials to populate (up to 420s)...
INFO: Dismissing "Extend Your Session" prompt during credentials wait...   ← Cancel clicked here
ERROR: Locator polling timed out after 420000ms                            ← session expired, credentials gone
```

Visual inspection of the live dialog confirmed:
- **"Cancel"** — outlined secondary button (dismisses without extending)
- **"Extend Session"** — filled purple primary button (extends by 4 hours; once per session)
- After clicking "Extend Session": "Session extended" confirmation appears with only an × close button

**Root cause:** Both the handler and the inline wait dismiss use Cancel instead of "Extend Session".
The fix is: (1) re-add `addLocatorHandler` with the confirmed exact label, and (2) fix the inline
wait dismiss to also try "Extend Session" first with the same 3000ms timeout.

---

## Reproduction

1. Have an AWS sandbox session near expiry
2. Run `make up`
3. Dialog appears during Start Sandbox (Step 2) OR during the 420s credential wait
4. Cancel clicked → session not extended → sandbox expires → timeout hit

---

## Fix

### Change 1 — Re-add `addLocatorHandler` with exact "Extend Session" button text

**Exact old block (lines 251–252, current state after `02d792a4` removed the handler):**

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
- `timeout: 3000` on `isVisible` gives the modal animation enough time to complete.
- Clicking "Extend Session" extends the sandbox by 4 hours. Dialog will not reappear after
  a successful extension ("This can only be done once per session").
- 500ms + Escape dismisses the "Session extended" (×-only) confirmation modal.
- Fallback to Escape handles the case where session was already extended (button not present).
- 250ms settle before returning lets the page stabilize before Playwright resumes the click.

---

### Change 2 — `_waitForCredentials` inline dismiss: use "Extend Session" instead of Cancel

**Exact old block (lines 437–447):**

```javascript
          const _extendDuringWait = page.locator('[role="dialog"]:has-text("Extend Your Session")').first();
          if (await _extendDuringWait.isVisible({ timeout: 500 }).catch(() => false)) {
            console.error('INFO: Dismissing "Extend Your Session" prompt during credentials wait...');
            const _cancelDuringWait = _extendDuringWait.locator('button:has-text("Cancel")').first();
            if (await _cancelDuringWait.isVisible({ timeout: 500 }).catch(() => false)) {
              await _cancelDuringWait.click({ force: true }).catch(() => {});
            } else {
              await page.keyboard.press('Escape').catch(() => {});
            }
            await page.waitForTimeout(300);
          }
```

**Exact new block:**

```javascript
          const _extendDuringWait = page.locator('[role="dialog"]:has-text("Extend Your Session")').first();
          if (await _extendDuringWait.isVisible({ timeout: 500 }).catch(() => false)) {
            console.error('INFO: Extending "Extend Your Session" prompt during credentials wait...');
            const _extendDuringWaitBtn = page.locator('[role="dialog"]:has-text("Extend Your Session") button:has-text("Extend Session")').first();
            if (await _extendDuringWaitBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
              await _extendDuringWaitBtn.click({ force: true }).catch(() => {});
              await page.waitForTimeout(500).catch(() => {});
              await page.keyboard.press('Escape').catch(() => {});
            } else {
              await page.keyboard.press('Escape').catch(() => {});
            }
            await page.waitForTimeout(300);
          }
```

**Why:**
- Same fix as Change 1 — "Extend Session" actually extends; Cancel does not.
- If the dialog appears during the wait and Cancel is clicked, the session expiry countdown
  continues. If the sandbox expires before credentials populate, the 420s timer hits.
- `timeout: 3000` matches the handler — needed for modal animation.
- Fallback to Escape handles the "already extended once" case (button not present).
- Log message changed from "Dismissing" to "Extending" to distinguish from proactive blocks.
- `waitForTimeout(300)` settle after the dismiss is unchanged.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/playwright/acg_credentials.js` | Re-add `addLocatorHandler` with exact `button:has-text("Extend Session")` (Change 1); fix inline wait dismiss from Cancel to "Extend Session" (Change 2) |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass (zero syntax errors)
- No other files touched

---

## Definition of Done

**Change 1 — addLocatorHandler:**
- [ ] `addLocatorHandler` block re-added at lines 251–252 (between the existing sandbox tab log and "Skip navigation" comment)
- [ ] Registered locator: `page.locator('[role="dialog"][data-open="true"]:has-text("Extend Your Session")')`
- [ ] Handler log: `'INFO: [handler] Clicking "Extend Session" to extend sandbox...'`
- [ ] Extend button selector: `'[role="dialog"]:has-text("Extend Your Session") button:has-text("Extend Session")'`
- [ ] `isVisible` timeout is `3000`
- [ ] After click: `waitForTimeout(500)` then `page.keyboard.press('Escape')`
- [ ] Fallback (button not visible): `page.keyboard.press('Escape')`
- [ ] Final settle: `waitForTimeout(250)`

**Change 2 — credential wait inline dismiss:**
- [ ] `button:has-text("Cancel")` is gone from the `_waitForCredentials` while-loop
- [ ] Replaced with `button:has-text("Extend Session")` with `timeout: 3000`
- [ ] After click: `waitForTimeout(500)` then `page.keyboard.press('Escape')`
- [ ] Fallback (button not visible): `page.keyboard.press('Escape')`
- [ ] Log changed to `'INFO: Extending "Extend Your Session" prompt during credentials wait...'`
- [ ] `waitForTimeout(300)` settle unchanged

**Both changes:**
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
- Do NOT use `button:has-text("Extend")` — use the full exact label `"Extend Session"`
- Do NOT use `button.pando-button--usage_filled` — previously matched the wrong element
- Do NOT use `timeout: 1000` for `isVisible` — modal animation requires 3000ms
- Do NOT change the proactive inline dismiss blocks BEFORE the start flow (lines ~367–400) — those are separate one-time checks that use Escape and are fine as-is
- Do NOT change the `waitForTimeout(300)` settle in Change 2 — only the button selector changes
