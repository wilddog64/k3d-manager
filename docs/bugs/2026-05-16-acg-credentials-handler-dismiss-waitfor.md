# Bug: acg_credentials — handler should dismiss (Cancel) and wait for dialog hidden, not try to extend

**Branch:** `k3d-manager-v1.4.6`
**File:** `scripts/lib/acg/playwright/acg_credentials.js`
**Supersedes:** `docs/bugs/2026-05-16-acg-credentials-extend-dialog-button-enumerate.md` (do NOT implement that spec)

---

## Problem

The handler currently tries to click an "Extend" button (1000ms timeout) then falls back to
Cancel. The Extend button does not exist in this dialog, so every invocation burns 1000ms on a
failed `isVisible()` call before falling back to Cancel. Total handler time: ~2000ms per fire.

The "Extend Your Session" dialog appears on a session timer (~8–10s interval when near expiry).
With ~2000ms per handler cycle + Playwright overhead ≈ 6–10s per cycle → 3 fires in 30s →
timeout. The fix is a **hard-dismiss path only** (Copilot's direction), with the wait replaced by
`waitFor({ state: 'hidden' })` + a short `waitForTimeout(500)` for CSS animation settle.

```
INFO: [handler] Auto-extending "Extend Your Session" prompt...  (×3)
ERROR: locator.click: Timeout 30000ms exceeded.
  3 × found locator ... intercepting action to run the handler
    - locator handler has finished, waiting for locator to be hidden
    - interception handler has finished, continuing
```

**Root cause:** 1000ms wasted on a missing Extend button + 1000ms blind wait = ~2000ms handler,
giving the session timer multiple opportunities to re-fire before the Start Sandbox click lands.

---

## Reproduction

1. Have a GCP sandbox session near expiry
2. Run `make up CLUSTER_PROVIDER=k3s-gcp`
3. "Extend Your Session" dialog appears during Start Sandbox (Step 2)
4. Handler fires 3× (each ~2s) — 30s timeout hit

---

## Fix

### Change 1 — `addLocatorHandler` callback: hard-dismiss path, waitFor hidden + 500ms settle

Replace the entire handler callback body. No other lines change.

**Exact old block:**

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

**Exact new block:**

```javascript
        console.error('INFO: [handler] Dismissing "Extend Your Session" prompt...');
        const _handlerCancelBtn = page.locator('[role="dialog"]:has-text("Extend Your Session") button:has-text("Cancel")').first();
        if (await _handlerCancelBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
          await _handlerCancelBtn.click({ force: true }).catch(() => {});
        } else {
          await page.keyboard.press('Escape').catch(() => {});
        }
        await page.locator('[role="dialog"][data-open="true"]:has-text("Extend Your Session")')
          .waitFor({ state: 'hidden', timeout: 5000 })
          .catch(() => {});
        await page.waitForTimeout(500).catch(() => {});
```

**Why this works:**
- Removes the `_handlerExtendBtn` branch entirely — no more 1000ms wasted on a button that does not exist.
- `_handlerCancelBtn.isVisible({ timeout: 1000 })` resolves immediately when Cancel IS present (< 100ms); falls back to Escape.
- `waitFor({ state: 'hidden' })` on `[data-open="true"]` exits the moment Cancel sets `data-open="false"` (near-instant) — semantically correct and eliminates the blind 1000ms wait.
- `waitForTimeout(500)` covers the ~400ms CSS slide-out animation so the Start Sandbox button is stable before Playwright retries the click (prevents Bug 3 reintroduction).
- Total handler time: ~100ms (Cancel click) + ~0ms (waitFor exits instantly) + 500ms = ~600ms vs ~2000ms before. In 30s this allows ~45 cycles instead of ~3, giving Playwright far more attempts between timer fires.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/playwright/acg_credentials.js` | Handler callback: dismiss-only with waitFor hidden + 500ms settle |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass (zero syntax errors)
- No other files touched
- Do NOT implement `docs/bugs/2026-05-16-acg-credentials-extend-dialog-button-enumerate.md` — it is superseded by this spec

---

## Definition of Done

- [ ] Handler callback body matches the exact new block above
- [ ] `_handlerExtendBtn` is gone — no reference to an "Extend" button
- [ ] `_handlerCancelBtn.isVisible({ timeout: 1000 })` is the first check (Cancel or Escape)
- [ ] `waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {})` is present after the if/else
- [ ] `waitForTimeout(500).catch(() => {})` is the last line before the closing `}`
- [ ] The old `waitForTimeout(1000)` is gone
- [ ] `node --check scripts/lib/acg/playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Commit message (exact): `fix(acg-credentials): dismiss-only handler with waitFor hidden + 500ms animation settle`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/acg/playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT implement the enumerate spec (`2026-05-16-acg-credentials-extend-dialog-button-enumerate.md`) — it is superseded
- Do NOT add an Extend button branch back — hard-dismiss (Cancel/Escape) only
- Do NOT remove the `[data-open="true"]` selector from the outer `addLocatorHandler` locator
- Do NOT use `waitForTimeout(1000)` — it is replaced by `waitFor` + `waitForTimeout(500)`
