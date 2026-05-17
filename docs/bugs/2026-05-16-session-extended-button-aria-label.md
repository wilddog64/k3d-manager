# Bug: acg — "Session extended" × button not clicked — `button.first()` finds wrong button

**Branch:** `k3d-manager-v1.4.6`
**Files:** `scripts/lib/acg/playwright/acg_credentials.js`, `scripts/lib/acg/playwright/acg_extend.js`

---

## Problem

The "Session extended" / "Your sandbox has been extended." card appears after extending the
sandbox session. Every location that tries to dismiss it calls:

```javascript
await <locator>.locator('button').first().click({ force: true }).catch(() => {});
```

`button.first()` inside the matched container finds a hidden action button (likely "Extend
Session" or "Cancel" from the parent dialog layered beneath), not the visible × close button.
The × button never receives the click — the card stays visible and blocks subsequent actions.

**Root cause:** `button` without `aria-label="Close"` is ambiguous inside the "Session
extended" card. The × close button carries `aria-label="Close"` (proven by the working fix
in `c66e8bc5` for the "Extend Your Session" dialog). All 7 dismiss calls must use
`button[aria-label="Close"]` instead of bare `button`.

---

## Reproduction

1. Run `make up` with `CLUSTER_PROVIDER=k3s-aws`
2. `acg_extend_playwright` extends the session — "Your sandbox has been extended." card appears
3. Any Playwright script that calls `.locator('button').first().click()` on the card locator
   clicks the wrong button — the card remains visible on screen

---

## Fix

Replace `'button'` → `'button[aria-label="Close"]'` in all 7 dismiss locations.

**Proof:** `c66e8bc5` used `button[aria-label="Close"]` to successfully dismiss the
"Extend Your Session" dialog — same ARIA pattern, same ACG React/Chakra UI framework.

---

### Change 1 — `acg_credentials.js` line 157: `_clickStartSandbox`

**Exact old block:**
```javascript
  const _sessionExtended = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
  if (await _sessionExtended.isVisible({ timeout: 2000 }).catch(() => false)) {
    await _sessionExtended.locator('button').first().click({ force: true }).catch(() => {});
    await _sessionExtended.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
  }
```

**Exact new block:**
```javascript
  const _sessionExtended = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
  if (await _sessionExtended.isVisible({ timeout: 2000 }).catch(() => false)) {
    await _sessionExtended.locator('button[aria-label="Close"]').first().click({ force: true }).catch(() => {});
    await _sessionExtended.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
  }
```

---

### Change 2 — `acg_credentials.js` line 274: `addLocatorHandler`

**Exact old block:**
```javascript
          const _sessionExtendedConfirm = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
          if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
            await _sessionExtendedConfirm.locator('button').first().click({ force: true }).catch(() => {});
            await _sessionExtendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
          }
        }
        await page.locator('[role="dialog"]:has-text("Extend Your Session")').waitFor({ state: 'hidden', timeout: 3000 }).catch(() => {});
```

**Exact new block:**
```javascript
          const _sessionExtendedConfirm = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
          if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
            await _sessionExtendedConfirm.locator('button[aria-label="Close"]').first().click({ force: true }).catch(() => {});
            await _sessionExtendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
          }
        }
        await page.locator('[role="dialog"]:has-text("Extend Your Session")').waitFor({ state: 'hidden', timeout: 3000 }).catch(() => {});
```

---

### Change 3 — `acg_credentials.js` line 383: proactive dismissal in `extractCredentials`

**Exact old block:**
```javascript
    const _sessionExtendedModal = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      await _sessionExtendedModal.locator('button').first().click({ force: true }).catch(() => {});
      await _sessionExtendedModal.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {
        console.error('WARN: "Session extended" modal did not close within 5s — proceeding anyway');
      });
    }

    // Dismiss "Extend Your Session" prompt — appears when a sandbox is about to expire
```

**Exact new block:**
```javascript
    const _sessionExtendedModal = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      await _sessionExtendedModal.locator('button[aria-label="Close"]').first().click({ force: true }).catch(() => {});
      await _sessionExtendedModal.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {
        console.error('WARN: "Session extended" modal did not close within 5s — proceeding anyway');
      });
    }

    // Dismiss "Extend Your Session" prompt — appears when a sandbox is about to expire
```

---

### Change 4 — `acg_credentials.js` line 470: `_waitForCredentials` poll loop

**Exact old block:**
```javascript
              const _sessionExtendedConfirm = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
              if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
                await _sessionExtendedConfirm.locator('button').first().click({ force: true }).catch(() => {});
                await _sessionExtendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
              }
            }
            await _extendDuringWait.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
```

**Exact new block:**
```javascript
              const _sessionExtendedConfirm = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
              if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
                await _sessionExtendedConfirm.locator('button[aria-label="Close"]').first().click({ force: true }).catch(() => {});
                await _sessionExtendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
              }
            }
            await _extendDuringWait.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
```

---

### Change 5 — `acg_extend.js` line 143: initial dismissal before extend button search

**Exact old block:**
```javascript
    const _sessionExtendedModal = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      await _sessionExtendedModal.locator('button').first().click({ force: true }).catch(() => {});
      await _sessionExtendedModal.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {
        console.error('WARN: "Session extended" modal did not close within 5s — proceeding anyway');
      });
    }

    // Wait for skeleton loaders to clear
```

**Exact new block:**
```javascript
    const _sessionExtendedModal = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      await _sessionExtendedModal.locator('button[aria-label="Close"]').first().click({ force: true }).catch(() => {});
      await _sessionExtendedModal.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {
        console.error('WARN: "Session extended" modal did not close within 5s — proceeding anyway');
      });
    }

    // Wait for skeleton loaders to clear
```

---

### Change 6 — `acg_extend.js` line 190: Immediate path post-click confirmation

**Exact old block:**
```javascript
      const _extendedConfirm = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
      if (await _extendedConfirm.isVisible({ timeout: 3000 }).catch(() => false)) {
        await _extendedConfirm.locator('button').first().click({ force: true }).catch(() => {});
        await _extendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
      }
      console.log('Extend action complete (Immediate).');
```

**Exact new block:**
```javascript
      const _extendedConfirm = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
      if (await _extendedConfirm.isVisible({ timeout: 3000 }).catch(() => false)) {
        await _extendedConfirm.locator('button[aria-label="Close"]').first().click({ force: true }).catch(() => {});
        await _extendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
      }
      console.log('Extend action complete (Immediate).');
```

---

### Change 7 — `acg_extend.js` line 389: general path post-extend confirmation

**Exact old block:**
```javascript
    const _extendedConfirmGeneral = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
    if (await _extendedConfirmGeneral.isVisible({ timeout: 2000 }).catch(() => false)) {
      await _extendedConfirmGeneral.locator('button').first().click({ force: true }).catch(() => {});
      await _extendedConfirmGeneral.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
    }

    const expiryText = await page.locator('text=/expires/i').first().textContent().catch(() => 'unknown');
```

**Exact new block:**
```javascript
    const _extendedConfirmGeneral = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
    if (await _extendedConfirmGeneral.isVisible({ timeout: 2000 }).catch(() => false)) {
      await _extendedConfirmGeneral.locator('button[aria-label="Close"]').first().click({ force: true }).catch(() => {});
      await _extendedConfirmGeneral.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
    }

    const expiryText = await page.locator('text=/expires/i').first().textContent().catch(() => 'unknown');
```

---

## Files Changed

| File | Changes |
|------|---------|
| `scripts/lib/acg/playwright/acg_credentials.js` | Changes 1–4 — 4 `'button'` → `'button[aria-label="Close"]'` |
| `scripts/lib/acg/playwright/acg_extend.js` | Changes 5–7 — 3 `'button'` → `'button[aria-label="Close"]'` |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass
- `node --check scripts/lib/acg/playwright/acg_extend.js` — must pass
- No other files touched
- Only the 7 listed `.locator('button')` calls change — all other lines unchanged

---

## Definition of Done

- [ ] All 7 `locator('button').first()` calls on "Session extended" card locators changed to `locator('button[aria-label="Close"]').first()`
- [ ] No other lines modified in either file
- [ ] `node --check scripts/lib/acg/playwright/acg_credentials.js` passes
- [ ] `node --check scripts/lib/acg/playwright/acg_extend.js` passes
- [ ] No other files modified
- [ ] Committed to `k3d-manager-v1.4.6`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

**Commit message (exact):**
```
fix(acg): use button[aria-label="Close"] to dismiss Session extended card — button.first() finds wrong button
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `acg_credentials.js` and `acg_extend.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT change any locator declarations — only the `.locator('button')` → `.locator('button[aria-label="Close"]')` inside each dismiss block
- Do NOT change `button:has-text("Extend Session")`, `button:has-text("Cancel")`, or any other button selector — only the 7 "Session extended" card dismiss calls
- Do NOT change the `_extendSessionPrompt` block that already correctly uses `button[aria-label="Close"]`
