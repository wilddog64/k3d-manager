# Bug: acg_credentials — "Extend Your Session" modal still blocks during sandbox wait and button-click phase

**Branch:** `k3d-manager-v1.4.6`
**File:** `scripts/lib/acg/playwright/acg_credentials.js`

---

## Problem

The "Extend Your Session" modal still blocks the script even after the pre-flight dismissal
block (commit `69204c91`) was added. The modal can appear at any point, but the current code
only checks for it at two specific moments:

1. A one-shot pre-flight check before the Start/Open flow (lines 364–377)
2. Inside `_waitForCredentials` during polling (lines 437–447)

**Gap:** The modal is NOT checked during:
- `_waitForSandboxEntry` — a 30-second `page.waitForFunction()` call (lines 390–431)
- The button-click sequence — `startButton.click()`, `_openBtnToClick.click()`, `startButton2.click()` (lines 475–524)

If the modal appears during these phases, the button click is intercepted by the modal
overlay, the sandbox is never started, and `_waitForCredentials` polling has nothing to wait for.

**Root cause:** Point-in-time checks cannot cover a modal that appears asynchronously at
any moment. The correct tool is `page.addLocatorHandler()` (Playwright ≥ 1.44, installed:
1.58.2), which fires automatically whenever the locator becomes visible — including during
`waitForFunction`, `waitForTimeout`, element visibility waits, and click actions.

---

## Reproduction

1. Have a GCP sandbox session near expiry (within ~10 minutes)
2. Run `make up CLUSTER_PROVIDER=k3s-gcp`
3. "Extend Your Session" modal appears during `_waitForSandboxEntry` or button-click phase
4. Start Sandbox / Open Sandbox click is intercepted — modal blocks
5. `_waitForCredentials` times out (420s) because no button was successfully clicked

---

## Fix

### Change 1 — Register `page.addLocatorHandler()` immediately after `page` is established

Insert the handler block between the page-establishment block and the
`// Skip navigation entirely` comment. The handler fires automatically at any point during
the script — no polling, no gaps.

**Exact old block:**

```javascript
    } else {
      console.error(`INFO: Found existing sandbox tab: ${page.url()}`);
    }

    // Skip navigation entirely if sandbox panel is already loaded on the current page
    const _sandboxReady = await page.locator(
```

**Exact new block:**

```javascript
    } else {
      console.error(`INFO: Found existing sandbox tab: ${page.url()}`);
    }

    // Auto-dismiss "Extend Your Session" at any point — fires during waitForFunction, clicks, etc.
    await page.addLocatorHandler(
      page.locator('[role="dialog"]:has-text("Extend Your Session")'),
      async () => {
        console.error('INFO: [handler] Auto-dismissing "Extend Your Session" prompt...');
        const _handlerCancelBtn = page.locator('[role="dialog"]:has-text("Extend Your Session") button:has-text("Cancel")').first();
        if (await _handlerCancelBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
          await _handlerCancelBtn.click({ force: true }).catch(() => {});
        } else {
          await page.keyboard.press('Escape').catch(() => {});
        }
      }
    );

    // Skip navigation entirely if sandbox panel is already loaded on the current page
    const _sandboxReady = await page.locator(
```

Only these lines change. Do NOT modify any other lines in the file.

**Why no `waitFor` at the end of the handler:** Playwright automatically waits for the
registered locator to become invisible after the handler returns before retrying the
intercepted action. An explicit `waitFor` inside the handler is redundant.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/playwright/acg_credentials.js` | Add `page.addLocatorHandler()` for "Extend Your Session" modal immediately after page is established |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass (zero syntax errors)
- No other files touched

---

## Definition of Done

- [ ] `scripts/lib/acg/playwright/acg_credentials.js` contains the `page.addLocatorHandler` block immediately before the `// Skip navigation entirely` comment
- [ ] `node --check scripts/lib/acg/playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Commit message: `fix(acg-credentials): auto-dismiss Extend Your Session modal via addLocatorHandler`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/acg/playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT remove the existing pre-flight dismissal block (lines 364–377) or the
  `_waitForCredentials` modal check — they are belt-and-suspenders and harmless
- Do NOT add `{ noWaitAfter: true }` to `addLocatorHandler` — the default behavior
  (wait for locator to become invisible after handler) is exactly what we want
