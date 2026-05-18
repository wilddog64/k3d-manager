# Bug: acg_extend — "Session extended" modal not closed; make up hangs

**Branch:** `k3d-manager-v1.4.6`
**Files:** `scripts/lib/acg/playwright/acg_extend.js`, `scripts/lib/acg/playwright/acg_credentials.js`

---

## Problem

After clicking "Extend Session", Pluralsight shows a "Session extended" confirmation modal
(dark card, only an × close button — no Escape key support). Both scripts try to close it
with `page.keyboard.press('Escape')`, but Escape does not dismiss this modal. The modal
stays open, blocks sandbox controls, and `make up` hangs indefinitely at the pre-flight TTL
extension step.

**Three broken locations in `acg_extend.js`:**
1. Initial dismissal (lines 140–156) — uses `text="Session extended"` locator (too narrow) +
   Escape + generic button selector that doesn't match the × button
2. After Immediate extend click (lines 196–199) — returns immediately without dismissing the
   confirmation modal that just appeared
3. General path (lines 387–392) — exits without dismissing the confirmation modal

**Two broken locations in `acg_credentials.js`:**
4. Handler callback (lines 267–270) — presses Escape when "Session extended" visible
5. `_waitForCredentials` inline dismiss (lines 469–472) — same

**Root cause:** The "Session extended" modal only has one button (×). Escape is not bound to
it. The scoped locator `_sessionExtendedModal.locator('button').first()` is the only reliable
way to close it.

---

## Reproduction

1. Run `make up` with a sandbox session near TTL expiry
2. "Extend Session" button is clicked (by handler or pre-flight)
3. "Session extended" modal appears
4. Escape is pressed — modal stays open
5. Pre-flight `acg_extend.js` starts with modal blocking the page
6. Extend button not found → 90s timeout → error, or hangs indefinitely if blocked upstream

---

## Fix

### Change 1 — `acg_extend.js` lines 139–156: Fix initial dismissal

**Exact old block:**

```javascript
    // Dismiss any lingering "Session extended" confirmation modal before searching for extend button
    const _sessionExtendedModal = page.locator('text="Session extended"').first();
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      await page.keyboard.press('Escape').catch(() => {});
      await page.waitForTimeout(500);
      // Fallback: click the X button if Escape didn't close it
      const _closeBtn = page.locator('[role="dialog"] button, button:has-text("×"), button[aria-label*="close" i]').first();
      if (await _sessionExtendedModal.isVisible({ timeout: 1000 }).catch(() => false) &&
          await _closeBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
        await _closeBtn.click({ force: true }).catch(() => {});
        await page.waitForTimeout(500);
      }
      // Confirm the modal is gone before proceeding — guards against slow close animations
      await _sessionExtendedModal.waitFor({ state: 'hidden', timeout: 3000 }).catch(() => {
        console.error('WARN: "Session extended" modal did not close within 3s — proceeding anyway');
      });
    }
```

**Exact new block:**

```javascript
    // Dismiss any lingering "Session extended" confirmation modal before searching for extend button
    const _sessionExtendedModal = page.locator('[role="dialog"]:has-text("Session extended")').first();
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      await _sessionExtendedModal.locator('button').first().click({ force: true }).catch(() => {});
      await _sessionExtendedModal.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {
        console.error('WARN: "Session extended" modal did not close within 5s — proceeding anyway');
      });
    }
```

**Why:** Scope the close button to the dialog itself (`_sessionExtendedModal.locator('button').first()`). The
"Session extended" dialog has exactly one button (×); this is the only reliable way to close it.
Escape, `button:has-text("×")`, and `button[aria-label*="close"]` all fail on this dialog.

---

### Change 2 — `acg_extend.js` lines 196–199: Dismiss modal after Immediate extend click

**Exact old block:**

```javascript
    if (clicked) {
      console.log('Extend action complete (Immediate).');
      return;
    }
```

**Exact new block:**

```javascript
    if (clicked) {
      const _extendedConfirm = page.locator('[role="dialog"]:has-text("Session extended")').first();
      if (await _extendedConfirm.isVisible({ timeout: 3000 }).catch(() => false)) {
        await _extendedConfirm.locator('button').first().click({ force: true }).catch(() => {});
        await _extendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
      }
      console.log('Extend action complete (Immediate).');
      return;
    }
```

**Why:** After clicking the extend button, Pluralsight shows the "Session extended" confirmation.
Without dismissal, the modal lingers and blocks sandbox controls for the next step (provisioning).

---

### Change 3 — `acg_extend.js` lines 387–392: Dismiss modal on general path before exit

**Exact old block:**

```javascript
    if (!confirmed) {
      console.error('WARN: Could not confirm extension via toast/TTL text — proceeding anyway');
    }

    const expiryText = await page.locator('text=/expires/i').first().textContent().catch(() => 'unknown');
    console.log(`Extend action complete. Current expiry text: ${expiryText}`);
```

**Exact new block:**

```javascript
    if (!confirmed) {
      console.error('WARN: Could not confirm extension via toast/TTL text — proceeding anyway');
    }

    const _extendedConfirmGeneral = page.locator('[role="dialog"]:has-text("Session extended")').first();
    if (await _extendedConfirmGeneral.isVisible({ timeout: 2000 }).catch(() => false)) {
      await _extendedConfirmGeneral.locator('button').first().click({ force: true }).catch(() => {});
      await _extendedConfirmGeneral.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
    }

    const expiryText = await page.locator('text=/expires/i').first().textContent().catch(() => 'unknown');
    console.log(`Extend action complete. Current expiry text: ${expiryText}`);
```

**Why:** Same modal lingering problem on the non-Immediate paths (via Open Sandbox or Auto Shutdown click).
Dismiss before logging exit so the next pipeline step starts with a clean page.

---

### Change 4 — `acg_credentials.js` lines 267–270: Fix handler Escape → button click

**Exact old block:**

```javascript
          const _sessionExtendedConfirm = page.locator('[role="dialog"]:has-text("Session extended")').first();
          if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
            await page.keyboard.press('Escape').catch(() => {});
          }
```

**Exact new block:**

```javascript
          const _sessionExtendedConfirm = page.locator('[role="dialog"]:has-text("Session extended")').first();
          if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
            await _sessionExtendedConfirm.locator('button').first().click({ force: true }).catch(() => {});
            await _sessionExtendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
          }
```

**Why:** Escape is unreliable on this modal. Clicking the scoped button closes it. Adding
`waitFor({ state: 'hidden' })` ensures the modal is fully gone before the handler returns.

---

### Change 5 — `acg_credentials.js` lines 469–472: Fix `_waitForCredentials` Escape → button click

**Exact old block:**

```javascript
              const _sessionExtendedConfirm = page.locator('[role="dialog"]:has-text("Session extended")').first();
              if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
                await page.keyboard.press('Escape').catch(() => {});
              }
```

**Exact new block:**

```javascript
              const _sessionExtendedConfirm = page.locator('[role="dialog"]:has-text("Session extended")').first();
              if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
                await _sessionExtendedConfirm.locator('button').first().click({ force: true }).catch(() => {});
                await _sessionExtendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
              }
```

**Why:** Same fix as Change 4, applied to the credential-wait loop.

---

### Change 6 — `acg_credentials.js` lines 373–388: Fix proactive dismissal Escape → button click

**Exact old block:**

```javascript
    // Dismiss any lingering "Session extended" modal that may obscure sandbox controls
    const _sessionExtendedModal = page.locator('text="Session extended"').first();
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      await page.keyboard.press('Escape').catch(() => {});
      await page.waitForTimeout(500);
      const _closeBtn = page.locator('[role="dialog"] button, button:has-text("×"), button[aria-label*="close" i]').first();
      if (await _sessionExtendedModal.isVisible({ timeout: 1000 }).catch(() => false) &&
          await _closeBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
        await _closeBtn.click({ force: true }).catch(() => {});
        await page.waitForTimeout(500);
      }
      await _sessionExtendedModal.waitFor({ state: 'hidden', timeout: 3000 }).catch(() => {
        console.error('WARN: "Session extended" modal did not close within 3s — proceeding anyway');
      });
    }
```

**Exact new block:**

```javascript
    // Dismiss any lingering "Session extended" modal that may obscure sandbox controls
    const _sessionExtendedModal = page.locator('[role="dialog"]:has-text("Session extended")').first();
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      await _sessionExtendedModal.locator('button').first().click({ force: true }).catch(() => {});
      await _sessionExtendedModal.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {
        console.error('WARN: "Session extended" modal did not close within 5s — proceeding anyway');
      });
    }
```

**Why:** Same pattern as Change 1 — fix locator from `text="Session extended"` to
`[role="dialog"]:has-text("Session extended")` and use scoped button click.

---

## Files Changed

| File | Changes |
|------|---------|
| `scripts/lib/acg/playwright/acg_extend.js` | Changes 1, 2, 3 — fix all three dismissal points |
| `scripts/lib/acg/playwright/acg_credentials.js` | Changes 4, 5, 6 — replace Escape with scoped button click |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_extend.js` — must pass
- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass
- No other files touched

---

## Definition of Done

**Change 1 — `acg_extend.js` initial dismissal:**
- [ ] Locator changed from `text="Session extended"` to `[role="dialog"]:has-text("Session extended")`
- [ ] `page.keyboard.press('Escape')`, `waitForTimeout(500)`, `_closeBtn` block removed
- [ ] `_sessionExtendedModal.locator('button').first().click({ force: true })` added
- [ ] `waitFor({ state: 'hidden', timeout: 5000 })` added

**Change 2 — `acg_extend.js` Immediate path:**
- [ ] `_extendedConfirm` locator + `isVisible({ timeout: 3000 })` guard added before `console.log`
- [ ] `locator('button').first().click({ force: true })` inside the guard
- [ ] `waitFor({ state: 'hidden', timeout: 5000 })` inside the guard
- [ ] `console.log('Extend action complete (Immediate).')` and `return` unchanged

**Change 3 — `acg_extend.js` general path:**
- [ ] `_extendedConfirmGeneral` locator + `isVisible({ timeout: 2000 })` guard added after `!confirmed` block
- [ ] `locator('button').first().click({ force: true })` inside the guard
- [ ] `waitFor({ state: 'hidden', timeout: 5000 })` inside the guard
- [ ] `expiryText` log line unchanged

**Change 4 — `acg_credentials.js` handler:**
- [ ] `page.keyboard.press('Escape')` removed
- [ ] `_sessionExtendedConfirm.locator('button').first().click({ force: true })` added
- [ ] `_sessionExtendedConfirm.waitFor({ state: 'hidden', timeout: 5000 })` added

**Change 5 — `acg_credentials.js` `_waitForCredentials`:**
- [ ] Same as Change 4

**Change 6 — `acg_credentials.js` proactive dismissal:**
- [ ] Locator changed from `text="Session extended"` to `[role="dialog"]:has-text("Session extended")`
- [ ] `page.keyboard.press('Escape')`, `waitForTimeout(500)`, `_closeBtn` block removed
- [ ] `_sessionExtendedModal.locator('button').first().click({ force: true })` added
- [ ] `waitFor({ state: 'hidden', timeout: 5000 })` added

**Both files:**
- [ ] `node --check` passes on both files
- [ ] No other lines touched
- [ ] No other files modified
- [ ] Commit message (exact): `fix(acg): close Session extended modal by clicking × button — Escape does not dismiss it`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the two listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT change `button:has-text("Extend Session")` selectors — those are for a different button
- Do NOT change `{ times: 1 }` on `addLocatorHandler`
- Do NOT change `_clickStartSandbox`
- Do NOT change `waitForTimeout(1000)` in the handler or `waitForTimeout(300)` in `_waitForCredentials`
- Do NOT change the `_extendDuringWait.waitFor({ state: 'hidden', timeout: 5000 })` line in `_waitForCredentials`
- Do NOT change the `page.locator('[role="dialog"]:has-text("Extend Your Session")').waitFor(...)` line in the handler
