# Bug: acg_credentials — addLocatorHandler intercepts and loops; remove it entirely

**Branch:** `k3d-manager-v1.4.6`
**File:** `scripts/lib/acg/playwright/acg_credentials.js`

---

## Problem

Every approach to handling "Extend Your Session" inside `addLocatorHandler` has failed:

```
INFO: [handler] Extending "Extend Your Session" prompt...
INFO: [handler] Extending "Extend Your Session" prompt...
INFO: [handler] Extending "Extend Your Session" prompt...
ERROR: locator.click: Timeout 30000ms exceeded.
  3 × found locator('[role="dialog"][data-open="true"]:has-text("Extend Your Session")'),
      intercepting action to run the handler
    - locator handler has finished, waiting for locator to be hidden   ← dialog DID close
    - interception handler has finished, continuing                     ← then immediately reappeared
```

The dialog closes after each handler fire (meaning the handler button click IS doing something),
then **immediately reappears** — meaning the session is not actually being extended. The handler
exhausts the 30s budget in 3 cycles.

**Root cause:** The Extend button selector is unknown and has resisted identification across 5+
attempts. Every dismiss (Cancel, Escape, or wrong filled button) closes the dialog briefly but
does not extend the session. `addLocatorHandler` intercepts the Start Sandbox click, loops until
budget exhausted, and times out.

**Why v1.4.5 worked without it:** v1.4.5 used plain `startButton.click()` with no handler. The
proactive inline dismiss blocks added in v1.4.6 (before the start flow, and inside the credential
wait loop) already handle the dialog when it is visible at checkpoints. If the dialog appears
mid-click, Playwright's 30s retry window gives it time to be dismissed at the next checkpoint.
The `addLocatorHandler` is making things worse by actively intercepting clicks that would
otherwise succeed.

---

## Reproduction

1. Have an AWS sandbox session near expiry
2. Run `make up`
3. "Extend Your Session" dialog appears during Start Sandbox (Step 2)
4. Handler fires 3×, each cycle dismisses without extending, 30s timeout hit

---

## Fix

### Change 1 — Remove the entire `addLocatorHandler` block

**Exact old block (lines 252–267):**

```javascript
    // Auto-dismiss "Extend Your Session" at any point — fires during waitForFunction, clicks, etc.
    await page.addLocatorHandler(
      page.locator('[role="dialog"][data-open="true"]:has-text("Extend Your Session")'),
      async () => {
        console.error('INFO: [handler] Extending "Extend Your Session" prompt...');
        const _extendBtn = page.locator('[role="dialog"]:has-text("Extend Your Session") button.pando-button--usage_filled').first();
        if (await _extendBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
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

**Exact new block (empty — delete all 16 lines):**

```javascript
```

**Why:** The `addLocatorHandler` approach requires knowing the exact Extend button selector. After
5+ attempts, this selector remains unknown. The proactive inline dismiss blocks already present
in the file handle the dialog before and during the start flow. Removing the handler restores
v1.4.5 behavior: plain `startButton.click()` retries for 30s, the proactive blocks handle any
visible dialog at checkpoints, and the click proceeds when the button is actionable.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/playwright/acg_credentials.js` | Remove `addLocatorHandler` block (16 lines) |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass (zero syntax errors)
- No other files touched

---

## Definition of Done

- [ ] `addLocatorHandler` call is gone — no reference anywhere in the file
- [ ] `page.locator('[role="dialog"][data-open="true"]:has-text("Extend Your Session")')` used as addLocatorHandler arg is gone
- [ ] The handler callback (with `_extendBtn`, `pando-button--usage_filled`, `Escape`) is gone
- [ ] The `// Auto-dismiss "Extend Your Session" at any point` comment is gone
- [ ] All other inline dismiss blocks remain untouched (proactive checks before start flow and inside credential wait loop)
- [ ] `startButton.click()` and `startButton2.click()` remain as plain `.click()` (no changes to call sites)
- [ ] No other lines touched
- [ ] `node --check scripts/lib/acg/playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Commit message (exact): `fix(acg-credentials): remove addLocatorHandler — inline proactive dismiss is sufficient`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/acg/playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT remove the inline proactive dismiss blocks — only the `addLocatorHandler` block goes
- Do NOT add a new `addLocatorHandler` with a different selector — the selector is unknown
- Do NOT change `startButton.click()` or `startButton2.click()` — they are already plain `.click()`
