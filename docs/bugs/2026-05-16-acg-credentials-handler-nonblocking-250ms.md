# Bug: acg_credentials — handler blocks on redundant waitFor, consumes entire 30s click budget

**Branch:** `k3d-manager-v1.4.6`
**File:** `scripts/lib/acg/playwright/acg_credentials.js`
**Supersedes:** `docs/bugs/2026-05-16-acg-credentials-handler-dismiss-waitfor.md` (do NOT implement that spec)

---

## Problem

The handler from the previous fix waits up to 5s for `[data-open="true"]` to become hidden
(`waitFor({ state: 'hidden', timeout: 5000 })`), plus 500ms settle. But `addLocatorHandler`
already has a built-in step that waits for the registered locator to disappear after the
handler returns — so we have two sequential waits. In the worst case the handler burns 5.5s
and Playwright's built-in waits for the remaining 24.5s, consuming the entire 30s click
budget in a single handler cycle.

**Result:** the click times out after exactly ONE handler fire (down from 3× in the previous
version) because the single cycle now exhausts the 30s window.

```
INFO: [handler] Dismissing "Extend Your Session" prompt...
ERROR: locator.click: Timeout 30000ms exceeded.
    - locator handler has finished, waiting for locator to be hidden
    - interception handler has finished, continuing
```

**Root cause:** `waitFor({ state: 'hidden', timeout: 5000 })` inside the handler is redundant
with Playwright's built-in post-handler hidden wait, and burns 5s of the 30s click budget per
cycle. Fix: remove the `waitFor` entirely and replace `waitForTimeout(500)` with
`waitForTimeout(250)`.

---

## Reproduction

1. Have a GCP sandbox session near expiry
2. Run `make up CLUSTER_PROVIDER=k3s-aws`
3. "Extend Your Session" dialog appears during Start Sandbox (Step 2)
4. Handler fires once — 30s timeout hit

---

## Fix

### Change 1 — handler callback: remove redundant `waitFor`, reduce settle to 250ms

**Exact old block:**

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

**Exact new block:**

```javascript
        console.error('INFO: [handler] Dismissing "Extend Your Session" prompt...');
        const _handlerCancelBtn = page.locator('[role="dialog"]:has-text("Extend Your Session") button:has-text("Cancel")').first();
        if (await _handlerCancelBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
          await _handlerCancelBtn.click({ force: true }).catch(() => {});
        } else {
          await page.keyboard.press('Escape').catch(() => {});
        }
        await page.waitForTimeout(250).catch(() => {});
```

**Why this works:**
- Removes the redundant `waitFor` — Playwright's built-in post-handler wait handles "wait for
  hidden" already; ours was consuming 5s per cycle for no benefit.
- Reduces settle from 500ms → 250ms — 250ms covers any brief post-dismiss rendering; the
  remaining stabilization is handled by Playwright's built-in hidden wait.
- Handler time drops from ~5.5s/cycle to ~350ms/cycle. With 30s budget: ~12 potential cycles
  instead of 1, giving Playwright far more opportunities to land the click between dialog fires.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/playwright/acg_credentials.js` | Handler: remove `waitFor`, reduce to `waitForTimeout(250)` |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass (zero syntax errors)
- No other files touched

---

## Definition of Done

- [ ] Handler callback body matches the exact new block above
- [ ] `waitFor({ state: 'hidden', timeout: 5000 })` is gone — no reference anywhere in the handler
- [ ] `waitForTimeout(250).catch(() => {})` is the last line before the closing `}`
- [ ] The old `waitForTimeout(500)` is gone
- [ ] `node --check scripts/lib/acg/playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Commit message (exact): `fix(acg-credentials): non-blocking handler — remove redundant waitFor, reduce settle to 250ms`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/acg/playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT implement `docs/bugs/2026-05-16-acg-credentials-handler-dismiss-waitfor.md` — superseded
- Do NOT re-add `waitFor({ state: 'hidden' })` — it is redundant with Playwright's built-in and harmful
- Do NOT use `waitForTimeout(500)` — replaced by `waitForTimeout(250)`
- Do NOT remove the Cancel/Escape dismiss path
- Do NOT remove the `[data-open="true"]` selector from the outer `addLocatorHandler` locator
