# Bug: acg — "Session extended" × not dismissed — `button[aria-label="Close"]` not found, no fallback

**Branch:** `k3d-manager-v1.4.6`
**Files:** `scripts/lib/acg/playwright/acg_credentials.js`, `scripts/lib/acg/playwright/acg_extend.js`

---

## Problem

All 7 "Session extended" dismiss calls use:

```javascript
await _CARD.locator('button[aria-label="Close"]').first().click({ force: true }).catch(() => {});
```

The `.catch(() => {})` silently swallows a "no element found" error when the × button does NOT carry
`aria-label="Close"` (ACG's Toast close button may use a different label, or may be a sibling of the
matched container rather than a child). No button is clicked, the card stays visible, and downstream
steps hang waiting for elements blocked by the card.

**Root cause:** `button[aria-label="Close"]` produces 0 matches inside the container; the .catch
swallows the error; no fallback exists. The notification card in ACG's UI (Chakra UI Toast) may
render its × as `button.last()` in the container with no aria-label, or with a label other than
`"Close"`.

**Fix:** For each dismiss call, check whether `button[aria-label="Close"]` exists in the container.
If it does, click it. If it does not, fall back to `button.last()` (the last button in the container,
which in a Toast is the × icon button). Log which path was taken so future failures are diagnosable.

---

## Reproduction

1. Run `make up` with `CLUSTER_PROVIDER=k3s-aws`
2. `acg_extend_playwright` or `acg_credentials.js` encounter the "Your sandbox has been extended."
   toast card
3. `button[aria-label="Close"]` locator finds 0 elements — `.catch` swallows the error
4. Card remains visible — downstream Playwright waits time out

---

## Fix

Replace the single `button[aria-label="Close"]` click line at each of the 7 dismiss sites with a
3-line count-check + fallback pattern. No other lines change.

**Replacement pattern** (where `_CARD` is the container locator variable at each site):

```javascript
// OLD (1 line):
await _CARD.locator('button[aria-label="Close"]').first().click({ force: true }).catch(() => {});

// NEW (3 lines):
const _hasClose = await _CARD.locator('button[aria-label="Close"]').count().catch(() => 0) > 0;
const _closeBtn = _hasClose ? _CARD.locator('button[aria-label="Close"]').first() : _CARD.locator('button').last();
await _closeBtn.click({ force: true }).catch(() => {});
```

---

### Change 1 — `acg_credentials.js` line 157: `_clickStartSandbox` (`_sessionExtended`)

**Exact old block:**
```javascript
  if (await _sessionExtended.isVisible({ timeout: 2000 }).catch(() => false)) {
      await _sessionExtended.locator('button[aria-label="Close"]').first().click({ force: true }).catch(() => {});
    await _sessionExtended.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
  }
```

**Exact new block:**
```javascript
  if (await _sessionExtended.isVisible({ timeout: 2000 }).catch(() => false)) {
    const _hasClose = await _sessionExtended.locator('button[aria-label="Close"]').count().catch(() => 0) > 0;
    const _closeBtn = _hasClose ? _sessionExtended.locator('button[aria-label="Close"]').first() : _sessionExtended.locator('button').last();
    await _closeBtn.click({ force: true }).catch(() => {});
    await _sessionExtended.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
  }
```

---

### Change 2 — `acg_credentials.js` line 274: `addLocatorHandler` (`_sessionExtendedConfirm`)

**Exact old block:**
```javascript
          if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
            await _sessionExtendedConfirm.locator('button[aria-label="Close"]').first().click({ force: true }).catch(() => {});
            await _sessionExtendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
          }
        }
        await page.locator('[role="dialog"]:has-text("Extend Your Session")').waitFor({ state: 'hidden', timeout: 3000 }).catch(() => {});
```

**Exact new block:**
```javascript
          if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
            const _hasClose = await _sessionExtendedConfirm.locator('button[aria-label="Close"]').count().catch(() => 0) > 0;
            const _closeBtn = _hasClose ? _sessionExtendedConfirm.locator('button[aria-label="Close"]').first() : _sessionExtendedConfirm.locator('button').last();
            await _closeBtn.click({ force: true }).catch(() => {});
            await _sessionExtendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
          }
        }
        await page.locator('[role="dialog"]:has-text("Extend Your Session")').waitFor({ state: 'hidden', timeout: 3000 }).catch(() => {});
```

---

### Change 3 — `acg_credentials.js` line 383: proactive dismissal (`_sessionExtendedModal`)

**Exact old block:**
```javascript
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      await _sessionExtendedModal.locator('button[aria-label="Close"]').first().click({ force: true }).catch(() => {});
      await _sessionExtendedModal.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {
        console.error('WARN: "Session extended" modal did not close within 5s — proceeding anyway');
      });
    }

    // Dismiss "Extend Your Session" prompt — appears when a sandbox is about to expire
```

**Exact new block:**
```javascript
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      const _hasClose = await _sessionExtendedModal.locator('button[aria-label="Close"]').count().catch(() => 0) > 0;
      const _closeBtn = _hasClose ? _sessionExtendedModal.locator('button[aria-label="Close"]').first() : _sessionExtendedModal.locator('button').last();
      await _closeBtn.click({ force: true }).catch(() => {});
      await _sessionExtendedModal.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {
        console.error('WARN: "Session extended" modal did not close within 5s — proceeding anyway');
      });
    }

    // Dismiss "Extend Your Session" prompt — appears when a sandbox is about to expire
```

---

### Change 4 — `acg_credentials.js` line 470: `_waitForCredentials` poll loop (`_sessionExtendedConfirm`)

**Exact old block:**
```javascript
              if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
                await _sessionExtendedConfirm.locator('button[aria-label="Close"]').first().click({ force: true }).catch(() => {});
                await _sessionExtendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
              }
            }
            await _extendDuringWait.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
```

**Exact new block:**
```javascript
              if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
                const _hasClose = await _sessionExtendedConfirm.locator('button[aria-label="Close"]').count().catch(() => 0) > 0;
                const _closeBtn = _hasClose ? _sessionExtendedConfirm.locator('button[aria-label="Close"]').first() : _sessionExtendedConfirm.locator('button').last();
                await _closeBtn.click({ force: true }).catch(() => {});
                await _sessionExtendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
              }
            }
            await _extendDuringWait.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
```

---

### Change 5 — `acg_extend.js` line 143: initial dismissal (`_sessionExtendedModal`)

**Exact old block:**
```javascript
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      await _sessionExtendedModal.locator('button[aria-label="Close"]').first().click({ force: true }).catch(() => {});
      await _sessionExtendedModal.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {
        console.error('WARN: "Session extended" modal did not close within 5s — proceeding anyway');
      });
    }

    // Wait for skeleton loaders to clear
```

**Exact new block:**
```javascript
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      const _hasClose = await _sessionExtendedModal.locator('button[aria-label="Close"]').count().catch(() => 0) > 0;
      const _closeBtn = _hasClose ? _sessionExtendedModal.locator('button[aria-label="Close"]').first() : _sessionExtendedModal.locator('button').last();
      await _closeBtn.click({ force: true }).catch(() => {});
      await _sessionExtendedModal.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {
        console.error('WARN: "Session extended" modal did not close within 5s — proceeding anyway');
      });
    }

    // Wait for skeleton loaders to clear
```

---

### Change 6 — `acg_extend.js` line 190: Immediate path (`_extendedConfirm`)

**Exact old block:**
```javascript
      if (await _extendedConfirm.isVisible({ timeout: 3000 }).catch(() => false)) {
        await _extendedConfirm.locator('button[aria-label="Close"]').first().click({ force: true }).catch(() => {});
        await _extendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
      }
      console.log('Extend action complete (Immediate).');
```

**Exact new block:**
```javascript
      if (await _extendedConfirm.isVisible({ timeout: 3000 }).catch(() => false)) {
        const _hasClose = await _extendedConfirm.locator('button[aria-label="Close"]').count().catch(() => 0) > 0;
        const _closeBtn = _hasClose ? _extendedConfirm.locator('button[aria-label="Close"]').first() : _extendedConfirm.locator('button').last();
        await _closeBtn.click({ force: true }).catch(() => {});
        await _extendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
      }
      console.log('Extend action complete (Immediate).');
```

---

### Change 7 — `acg_extend.js` line 389: general path (`_extendedConfirmGeneral`)

**Exact old block:**
```javascript
    if (await _extendedConfirmGeneral.isVisible({ timeout: 2000 }).catch(() => false)) {
      await _extendedConfirmGeneral.locator('button[aria-label="Close"]').first().click({ force: true }).catch(() => {});
      await _extendedConfirmGeneral.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
    }

    const expiryText = await page.locator('text=/expires/i').first().textContent().catch(() => 'unknown');
```

**Exact new block:**
```javascript
    if (await _extendedConfirmGeneral.isVisible({ timeout: 2000 }).catch(() => false)) {
      const _hasClose = await _extendedConfirmGeneral.locator('button[aria-label="Close"]').count().catch(() => 0) > 0;
      const _closeBtn = _hasClose ? _extendedConfirmGeneral.locator('button[aria-label="Close"]').first() : _extendedConfirmGeneral.locator('button').last();
      await _closeBtn.click({ force: true }).catch(() => {});
      await _extendedConfirmGeneral.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
    }

    const expiryText = await page.locator('text=/expires/i').first().textContent().catch(() => 'unknown');
```

---

## Files Changed

| File | Changes |
|------|---------|
| `scripts/lib/acg/playwright/acg_credentials.js` | Changes 1–4 — 4 sites: single click line → 3-line count+fallback |
| `scripts/lib/acg/playwright/acg_extend.js` | Changes 5–7 — 3 sites: single click line → 3-line count+fallback |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass
- `node --check scripts/lib/acg/playwright/acg_extend.js` — must pass
- No other files touched
- Only the 7 listed dismiss call sites change — all surrounding lines unchanged

---

## Definition of Done

- [ ] All 7 dismiss sites updated with the 3-line count+fallback pattern
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
fix(acg): fall back to button.last() when button[aria-label="Close"] not found in Session extended card
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `acg_credentials.js` and `acg_extend.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT change any container locator declarations — only the single dismiss click line at each site
- Do NOT change any other button selectors (Extend Session, Cancel, Start Sandbox, etc.)
- Do NOT combine with any other change in the same commit
