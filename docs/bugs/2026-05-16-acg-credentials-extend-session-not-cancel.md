# Bug: acg_credentials — handler clicks Cancel instead of Extend, dialog reappears 5× and times out

**Branch:** `k3d-manager-v1.4.6`
**File:** `scripts/lib/acg/playwright/acg_credentials.js`

---

## Problem

After the `waitForTimeout(1000)` fix (commit `0fbdba30`), the handler lets the page settle
so `startButton2.click()` lands cleanly. But the click landing is itself what triggers the
"Extend Your Session" dialog — the ACG platform requires a session extension before a sandbox
can start. The handler clicks Cancel, which dismisses the dialog without extending. Playwright
retries `startButton2.click()`, the platform shows the dialog again, Cancel is clicked — this
repeats 5× until the 30-second timeout expires.

```
INFO: Clicking Start Sandbox (Step 2)...
INFO: [handler] Auto-dismissing "Extend Your Session" prompt...  (×5)
ERROR: locator.click: Timeout 30000ms exceeded.
Call log:
  - waiting for locator('button:has-text("Start Sandbox")').first()
    5 × found locator('[role="dialog"][data-open="true"]:has-text("Extend Your Session")'), intercepting action to run the handler
      - locator handler has finished, waiting for locator('[role="dialog"][data-open="true"]:has-text("Extend Your Session")') to be hidden
      - interception handler has finished, continuing
```

**Root cause:** The handler clicks Cancel instead of Extend. Cancel dismisses the dialog
without granting the session extension. "Start Sandbox" is retried, triggers the dialog
again, and the cycle repeats until the 30s timeout.

---

## Reproduction

1. Have a GCP sandbox session near expiry
2. Run `make up CLUSTER_PROVIDER=k3s-gcp`
3. "Open Sandbox" clicked → "Start Sandbox (Step 2)" clicked
4. "Extend Your Session" dialog appears
5. Handler fires, clicks Cancel — dialog dismissed
6. Playwright retries "Start Sandbox" — dialog appears again
7. Repeats 5× until 30s timeout

---

## Fix

### Change 1 — `addLocatorHandler` callback: try Extend first, Cancel as fallback

Replace the handler callback body (lines 256–263). No other lines change.

**Exact old block:**

```javascript
        console.error('INFO: [handler] Auto-dismissing "Extend Your Session" prompt...');
        const _handlerCancelBtn = page.locator('[role="dialog"]:has-text("Extend Your Session") button:has-text("Cancel")').first();
        if (await _handlerCancelBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
          await _handlerCancelBtn.click({ force: true }).catch(() => {});
        } else {
          await page.keyboard.press('Escape').catch(() => {});
        }
        await page.waitForTimeout(1000).catch(() => {});
```

**Exact new block:**

```javascript
        console.error('INFO: [handler] Auto-extending "Extend Your Session" prompt...');
        const _handlerExtendBtn = page.locator('[role="dialog"]:has-text("Extend Your Session") button:has-text("Extend")').first();
        const _handlerCancelBtn = page.locator('[role="dialog"]:has-text("Extend Your Session") button:has-text("Cancel")').first();
        if (await _handlerExtendBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
          await _handlerExtendBtn.click({ force: true }).catch(() => {});
          await page.waitForTimeout(500).catch(() => {});
          await page.keyboard.press('Escape').catch(() => {});
        } else if (await _handlerCancelBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
          await _handlerCancelBtn.click({ force: true }).catch(() => {});
        } else {
          await page.keyboard.press('Escape').catch(() => {});
        }
        await page.waitForTimeout(1000).catch(() => {});
```

**Why this works:**
- Clicking "Extend" grants the session extension the platform requires before starting the sandbox.
  After extension the platform allows the "Start Sandbox" click and the handler fires at most once.
- The 500ms pause + Escape after Extend dismisses the "Session extended" confirmation dialog
  that the platform shows immediately after a successful extension.
- The trailing `waitForTimeout(1000)` (unchanged) lets the page settle before the handler returns.
- If "Extend" is not visible (button text differs or dialog has a different structure), the handler
  falls back to Cancel, then to Escape — so no regression on other dialog variants.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/playwright/acg_credentials.js` | Handler callback: try Extend first, Cancel as fallback |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass (zero syntax errors)
- No other files touched

---

## Definition of Done

- [ ] `scripts/lib/acg/playwright/acg_credentials.js` handler callback matches the exact new block above
- [ ] `button:has-text("Extend")` is tried first; `button:has-text("Cancel")` is the fallback; Escape is last resort
- [ ] The 500ms wait + Escape is present inside the Extend branch, after the Extend click
- [ ] The trailing `await page.waitForTimeout(1000).catch(() => {});` is unchanged (still last line before closing `}`)
- [ ] `node --check scripts/lib/acg/playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Commit message (exact): `fix(acg-credentials): click Extend instead of Cancel on Extend Your Session dialog`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/acg/playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT remove the `[data-open="true"]` selector from the `addLocatorHandler` locator — it is still needed
- Do NOT remove the trailing `waitForTimeout(1000)` — it is still needed for page settle
- Do NOT remove the Cancel and Escape fallbacks — needed when "Extend" button is not found
- Do NOT add `{ noWaitAfter: true }` to `addLocatorHandler`
- Do NOT change the pre-flight check (the `_extendSessionPrompt` block) — that is a separate code path
