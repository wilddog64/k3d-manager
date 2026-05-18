# Bug: acg_credentials — Escape fires without dialog confirmation, closes credentials panel

**Branch:** `k3d-manager-v1.4.6`
**File:** `scripts/lib/acg/playwright/acg_credentials.js`

---

## Problem

Two places press `Escape` unconditionally — both can close the credentials slide-over instead
of a dialog:

**Location 1 — `addLocatorHandler` callback (lines 267–270):**
```javascript
await page.waitForTimeout(500).catch(() => {});
await page.keyboard.press('Escape').catch(() => {});  // Case A — no "Session extended" check
} else {
  await page.keyboard.press('Escape').catch(() => {});  // Case B — button not present
```
- Case A: Escape is pressed 500ms after clicking "Extend Session" without confirming the
  "Session extended" confirmation dialog (Image #17) has appeared. If the modal animation
  takes longer than 500ms, Escape fires on whatever is focused — potentially closing the
  credentials slide-over.
- Case B: Escape is pressed when `button:has-text("Extend Session")` is not visible. If the
  session has already been extended once, the button is absent and Escape hits the page directly.

**Location 2 — `_waitForCredentials` inline dismiss (lines 467–471):**
```javascript
await page.waitForTimeout(500).catch(() => {});
await page.keyboard.press('Escape').catch(() => {});  // Case A — same timing problem
} else {
  await page.keyboard.press('Escape').catch(() => {});  // Case B — button not present
```
Same two cases, but now the credentials panel **is open** when the loop runs. An Escape that
hits the panel closes the slide-over; credentials never populate; 420s timer exhausts.

**User-confirmed dialog anatomy:**
- Image #16 — "Extend Your Session" dialog: Cancel (outlined) + "Extend Session" (filled purple)
- Image #17 — "Session extended" confirmation: only × close button

**Rule:** Only click "Extend Session" if the button is present. Only press Escape if
"Session extended" (Image #17) is confirmed visible. Never press Escape as a fallback.

---

## Reproduction

1. Run `make up` with a sandbox near TTL expiry
2. "Extend Your Session" dialog appears during credential wait
3. Handler or inline dismiss presses Escape without confirming "Session extended" appeared
4. Escape closes the credentials slide-over → 420s timeout

---

## Fix

### Change 1 — `addLocatorHandler` callback: remove fallback Escape, use `isVisible` before Escape

**Exact old block (lines 262–272):**

```javascript
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
```

**Exact new block:**

```javascript
      async () => {
        console.error('INFO: [handler] Clicking "Extend Session" to extend sandbox...');
        const _extendBtn = page.locator('[role="dialog"]:has-text("Extend Your Session") button:has-text("Extend Session")').first();
        if (await _extendBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
          await _extendBtn.click({ force: true }).catch(() => {});
          const _sessionExtendedConfirm = page.locator('[role="dialog"]:has-text("Session extended")').first();
          if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
            await page.keyboard.press('Escape').catch(() => {});
          }
        }
        await page.locator('[role="dialog"]:has-text("Extend Your Session")').waitFor({ state: 'hidden', timeout: 3000 }).catch(() => {});
        await page.waitForTimeout(1000).catch(() => {});
      },
```

**Why:**
- `page.keyboard.press('Escape')` is now only called when `[role="dialog"]:has-text("Session extended")` is confirmed visible — not blindly after 500ms. If the confirmation hasn't appeared within 2000ms, Escape is skipped entirely.
- The `else { Escape }` fallback is removed. When "Extend Session" button is absent, do nothing — no Escape.
- `waitFor({ state: 'hidden', timeout: 3000 })` on the "Extend Your Session" locator ensures the dialog is fully gone before the handler returns and Playwright resumes the intercepted click.
- `waitForTimeout(1000)` settle is unchanged.

---

### Change 2 — `_waitForCredentials` inline dismiss: same fix

**Exact old block (lines 463–474):**

```javascript
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

**Exact new block:**

```javascript
          if (await _extendDuringWait.isVisible({ timeout: 500 }).catch(() => false)) {
            console.error('INFO: Extending "Extend Your Session" prompt during credentials wait...');
            const _extendDuringWaitBtn = page.locator('[role="dialog"]:has-text("Extend Your Session") button:has-text("Extend Session")').first();
            if (await _extendDuringWaitBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
              await _extendDuringWaitBtn.click({ force: true }).catch(() => {});
              const _sessionExtendedConfirm = page.locator('[role="dialog"]:has-text("Session extended")').first();
              if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
                await page.keyboard.press('Escape').catch(() => {});
              }
            }
            await _extendDuringWait.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
            await page.waitForTimeout(300);
          }
```

**Why:**
- Same fix as Change 1. Escape only fires when "Session extended" (Image #17) is confirmed present.
- Fallback Escape removed — if button not present, wait for dialog to close on its own.
- `_extendDuringWait.waitFor({ state: 'hidden', timeout: 5000 })` ensures dialog is gone before the credential check continues.
- `waitForTimeout(300)` settle is unchanged.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/playwright/acg_credentials.js` | Fix handler callback (Change 1); fix `_waitForCredentials` inline dismiss (Change 2) — targeted Escape only when "Session extended" confirmed visible, remove fallback Escape |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass (zero syntax errors)
- No other files touched

---

## Definition of Done

**Change 1 — handler callback:**
- [ ] `await page.waitForTimeout(500).catch(() => {})` before Escape is gone
- [ ] `else { await page.keyboard.press('Escape').catch(() => {}); }` fallback is gone
- [ ] `const _sessionExtendedConfirm = page.locator('[role="dialog"]:has-text("Session extended")').first()` added inside the `if (_extendBtn.isVisible)` block
- [ ] `page.keyboard.press('Escape')` only inside `if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }))`
- [ ] `await page.locator('[role="dialog"]:has-text("Extend Your Session")').waitFor({ state: 'hidden', timeout: 3000 }).catch(() => {})` added before `waitForTimeout(1000)`
- [ ] `waitForTimeout(1000)` settle unchanged

**Change 2 — `_waitForCredentials` inline dismiss:**
- [ ] `await page.waitForTimeout(500).catch(() => {})` before Escape is gone
- [ ] `else { await page.keyboard.press('Escape').catch(() => {}); }` fallback is gone
- [ ] `const _sessionExtendedConfirm = page.locator('[role="dialog"]:has-text("Session extended")').first()` added inside the `if (_extendDuringWaitBtn.isVisible)` block
- [ ] `page.keyboard.press('Escape')` only inside `if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }))`
- [ ] `await _extendDuringWait.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {})` added after the if/else
- [ ] `waitForTimeout(300)` settle unchanged

**Both changes:**
- [ ] No other lines touched
- [ ] `node --check scripts/lib/acg/playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Commit message (exact): `fix(acg-credentials): targeted Escape only when Session extended confirmed — remove fallback Escape`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/acg/playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT change `button:has-text("Extend Session")` selector or its `timeout: 3000`
- Do NOT change `{ times: 1 }` on `addLocatorHandler` — that fix stays
- Do NOT change the `_clickStartSandbox` helper
- Do NOT change the proactive dismiss blocks BEFORE the start flow (lines ~372–402)
- Do NOT change `waitForTimeout(1000)` in the handler or `waitForTimeout(300)` in the inline dismiss
- Do NOT press Escape unconditionally anywhere in these two locations
