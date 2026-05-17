# Bug: acg — "Session extended" × never clicked — container `isVisible()` returns false, wrong button fallback

**Branch:** `k3d-manager-v1.4.6`
**Files:** `scripts/lib/acg/playwright/acg_credentials.js`, `scripts/lib/acg/playwright/acg_extend.js`

---

## Problem

All 7 dismiss sites use a container locator:

```javascript
page.locator(':has-text("Your sandbox has been extended."):has(button)').last()
```

Two compounding failures:

1. **`isVisible()` returns false on the container** — Playwright evaluates visibility on the
   broad container element (which may have no explicit dimensions or an ancestor with
   `overflow: hidden`). The `if` block is skipped entirely; no click ever fires.

2. **`button[aria-label="Close"]` (capital C) finds 0 matches** — Chakra UI v2 renders the
   Toast close button with `aria-label="close"` (lowercase). The CSS attribute selector is
   case-sensitive, so count = 0, and the fallback `button.last()` inside the broad container
   clicks the wrong button (a copy button in the credentials table, not the × icon).

Both failures result in the "Session extended" toast remaining permanently visible, blocking
downstream Playwright waits and causing `make up` to hang.

**Root cause:** Detection (`isVisible`) and click are both scoped to the wrong element.

---

## Reproduction

1. Run `make up` with `CLUSTER_PROVIDER=k3s-aws`
2. The "Extend Your Session" dialog fires during credential extraction
3. The extension completes — "Session extended" toast appears
4. `isVisible()` on the broad container returns false → dismiss block skipped
5. Toast remains visible — `acg_extend.js` subsequently hangs
6. `make up` times out or fails

---

## Fix

At all 7 dismiss sites, replace:
- The container locator (detection + waitFor) with the **exact text element** — `text="Your sandbox has been extended."` with `.first()`. A text-level locator has proper dimensions and is reliably visible.
- The 3-line count+fallback click block with a **2-line page-level CI click**:
  1. Count `button[aria-label="Close" i]` (case-insensitive) at page level
  2. If found, click it; if not, fall back to `[role="alert"] button, [role="status"] button` (first button in any Chakra alert/status container)

---

### Pattern applied at all 7 sites

**OLD (3 lines — count+fallback):**
```javascript
const _hasClose = await _CARD.locator('button[aria-label="Close"]').count().catch(() => 0) > 0;
const _closeBtn = _hasClose ? _CARD.locator('button[aria-label="Close"]').first() : _CARD.locator('button').last();
await _closeBtn.click({ force: true }).catch(() => {});
```

**NEW (2 lines — page-level CI + role fallback):**
```javascript
const _hasCIClose = await page.locator('button[aria-label="Close" i]').count().catch(() => 0) > 0;
await (_hasCIClose ? page.locator('button[aria-label="Close" i]').first() : page.locator('[role="alert"] button, [role="status"] button').first()).click({ force: true }).catch(() => {});
```

---

### Change 1 — `acg_credentials.js`: `_clickStartSandbox` (`_sessionExtended`)

**Exact old block:**
```javascript
  const _sessionExtended = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
  if (await _sessionExtended.isVisible({ timeout: 2000 }).catch(() => false)) {
    const _hasClose = await _sessionExtended.locator('button[aria-label="Close"]').count().catch(() => 0) > 0;
    const _closeBtn = _hasClose ? _sessionExtended.locator('button[aria-label="Close"]').first() : _sessionExtended.locator('button').last();
    await _closeBtn.click({ force: true }).catch(() => {});
    await _sessionExtended.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
  }
```

**Exact new block:**
```javascript
  const _sessionExtended = page.locator('text="Your sandbox has been extended."').first();
  if (await _sessionExtended.isVisible({ timeout: 2000 }).catch(() => false)) {
    const _hasCIClose = await page.locator('button[aria-label="Close" i]').count().catch(() => 0) > 0;
    await (_hasCIClose ? page.locator('button[aria-label="Close" i]').first() : page.locator('[role="alert"] button, [role="status"] button').first()).click({ force: true }).catch(() => {});
    await _sessionExtended.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
  }
```

---

### Change 2 — `acg_credentials.js`: `addLocatorHandler` (`_sessionExtendedConfirm`)

**Exact old block:**
```javascript
          const _sessionExtendedConfirm = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
          if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
            const _hasClose = await _sessionExtendedConfirm.locator('button[aria-label="Close"]').count().catch(() => 0) > 0;
            const _closeBtn = _hasClose ? _sessionExtendedConfirm.locator('button[aria-label="Close"]').first() : _sessionExtendedConfirm.locator('button').last();
            await _closeBtn.click({ force: true }).catch(() => {});
            await _sessionExtendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
          }
```

**Exact new block:**
```javascript
          const _sessionExtendedConfirm = page.locator('text="Your sandbox has been extended."').first();
          if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
            const _hasCIClose = await page.locator('button[aria-label="Close" i]').count().catch(() => 0) > 0;
            await (_hasCIClose ? page.locator('button[aria-label="Close" i]').first() : page.locator('[role="alert"] button, [role="status"] button').first()).click({ force: true }).catch(() => {});
            await _sessionExtendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
          }
```

---

### Change 3 — `acg_credentials.js`: proactive dismissal (`_sessionExtendedModal`)

**Exact old block:**
```javascript
    const _sessionExtendedModal = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      const _hasClose = await _sessionExtendedModal.locator('button[aria-label="Close"]').count().catch(() => 0) > 0;
      const _closeBtn = _hasClose ? _sessionExtendedModal.locator('button[aria-label="Close"]').first() : _sessionExtendedModal.locator('button').last();
      await _closeBtn.click({ force: true }).catch(() => {});
      await _sessionExtendedModal.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {
        console.error('WARN: "Session extended" modal did not close within 5s — proceeding anyway');
      });
    }
```

**Exact new block:**
```javascript
    const _sessionExtendedModal = page.locator('text="Your sandbox has been extended."').first();
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      const _hasCIClose = await page.locator('button[aria-label="Close" i]').count().catch(() => 0) > 0;
      await (_hasCIClose ? page.locator('button[aria-label="Close" i]').first() : page.locator('[role="alert"] button, [role="status"] button').first()).click({ force: true }).catch(() => {});
      await _sessionExtendedModal.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {
        console.error('WARN: "Session extended" modal did not close within 5s — proceeding anyway');
      });
    }
```

---

### Change 4 — `acg_credentials.js`: `_waitForCredentials` poll loop (`_sessionExtendedConfirm`)

**Exact old block:**
```javascript
              const _sessionExtendedConfirm = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
              if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
                const _hasClose = await _sessionExtendedConfirm.locator('button[aria-label="Close"]').count().catch(() => 0) > 0;
                const _closeBtn = _hasClose ? _sessionExtendedConfirm.locator('button[aria-label="Close"]').first() : _sessionExtendedConfirm.locator('button').last();
                await _closeBtn.click({ force: true }).catch(() => {});
                await _sessionExtendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
              }
```

**Exact new block:**
```javascript
              const _sessionExtendedConfirm = page.locator('text="Your sandbox has been extended."').first();
              if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
                const _hasCIClose = await page.locator('button[aria-label="Close" i]').count().catch(() => 0) > 0;
                await (_hasCIClose ? page.locator('button[aria-label="Close" i]').first() : page.locator('[role="alert"] button, [role="status"] button').first()).click({ force: true }).catch(() => {});
                await _sessionExtendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
              }
```

---

### Change 5 — `acg_extend.js`: initial dismissal (`_sessionExtendedModal`)

**Exact old block:**
```javascript
    const _sessionExtendedModal = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      const _hasClose = await _sessionExtendedModal.locator('button[aria-label="Close"]').count().catch(() => 0) > 0;
      const _closeBtn = _hasClose ? _sessionExtendedModal.locator('button[aria-label="Close"]').first() : _sessionExtendedModal.locator('button').last();
      await _closeBtn.click({ force: true }).catch(() => {});
      await _sessionExtendedModal.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {
        console.error('WARN: "Session extended" modal did not close within 5s — proceeding anyway');
      });
    }
```

**Exact new block:**
```javascript
    const _sessionExtendedModal = page.locator('text="Your sandbox has been extended."').first();
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      const _hasCIClose = await page.locator('button[aria-label="Close" i]').count().catch(() => 0) > 0;
      await (_hasCIClose ? page.locator('button[aria-label="Close" i]').first() : page.locator('[role="alert"] button, [role="status"] button').first()).click({ force: true }).catch(() => {});
      await _sessionExtendedModal.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {
        console.error('WARN: "Session extended" modal did not close within 5s — proceeding anyway');
      });
    }
```

---

### Change 6 — `acg_extend.js`: Immediate path (`_extendedConfirm`)

**Exact old block:**
```javascript
      const _extendedConfirm = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
      if (await _extendedConfirm.isVisible({ timeout: 3000 }).catch(() => false)) {
        const _hasClose = await _extendedConfirm.locator('button[aria-label="Close"]').count().catch(() => 0) > 0;
        const _closeBtn = _hasClose ? _extendedConfirm.locator('button[aria-label="Close"]').first() : _extendedConfirm.locator('button').last();
        await _closeBtn.click({ force: true }).catch(() => {});
        await _extendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
      }
```

**Exact new block:**
```javascript
      const _extendedConfirm = page.locator('text="Your sandbox has been extended."').first();
      if (await _extendedConfirm.isVisible({ timeout: 3000 }).catch(() => false)) {
        const _hasCIClose = await page.locator('button[aria-label="Close" i]').count().catch(() => 0) > 0;
        await (_hasCIClose ? page.locator('button[aria-label="Close" i]').first() : page.locator('[role="alert"] button, [role="status"] button').first()).click({ force: true }).catch(() => {});
        await _extendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
      }
```

---

### Change 7 — `acg_extend.js`: general path (`_extendedConfirmGeneral`)

**Exact old block:**
```javascript
    const _extendedConfirmGeneral = page.locator(':has-text("Your sandbox has been extended."):has(button)').last();
    if (await _extendedConfirmGeneral.isVisible({ timeout: 2000 }).catch(() => false)) {
      const _hasClose = await _extendedConfirmGeneral.locator('button[aria-label="Close"]').count().catch(() => 0) > 0;
      const _closeBtn = _hasClose ? _extendedConfirmGeneral.locator('button[aria-label="Close"]').first() : _extendedConfirmGeneral.locator('button').last();
      await _closeBtn.click({ force: true }).catch(() => {});
      await _extendedConfirmGeneral.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
    }
```

**Exact new block:**
```javascript
    const _extendedConfirmGeneral = page.locator('text="Your sandbox has been extended."').first();
    if (await _extendedConfirmGeneral.isVisible({ timeout: 2000 }).catch(() => false)) {
      const _hasCIClose = await page.locator('button[aria-label="Close" i]').count().catch(() => 0) > 0;
      await (_hasCIClose ? page.locator('button[aria-label="Close" i]').first() : page.locator('[role="alert"] button, [role="status"] button').first()).click({ force: true }).catch(() => {});
      await _extendedConfirmGeneral.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
    }
```

---

## Files Changed

| File | Changes |
|------|---------|
| `scripts/lib/acg/playwright/acg_credentials.js` | Changes 1–4 — 4 sites |
| `scripts/lib/acg/playwright/acg_extend.js` | Changes 5–7 — 3 sites |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass
- `node --check scripts/lib/acg/playwright/acg_extend.js` — must pass
- No other files touched
- Only the 7 listed dismiss blocks change — all surrounding lines unchanged

---

## Definition of Done

- [ ] All 7 dismiss sites updated with text-locator + page-level CI close pattern
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
fix(acg): text-locator + page-level case-insensitive close for Session extended toast
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `acg_credentials.js` and `acg_extend.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT change any container locator declarations beyond the 7 listed dismiss sites
- Do NOT change any other button selectors (Extend Session, Cancel, Start Sandbox, etc.)
- Do NOT combine with any other change in the same commit
