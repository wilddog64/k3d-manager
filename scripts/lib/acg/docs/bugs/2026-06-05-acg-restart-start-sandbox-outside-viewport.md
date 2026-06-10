# Bugfix: v0.1.3 — acg_restart Start Sandbox clicks missing scrollIntoViewIfNeeded

**Branch:** `feat/v0.1.3`
**Files:** `playwright/acg_restart.js`, `CHANGELOG.md`, `memory-bank/activeContext.md`, `memory-bank/progress.md`

---

## Problem

`acg_restart.js` has two paths that click a Start Sandbox button without first scrolling
it into view. Both fail with `locator.click: Element is outside of the viewport` when the
sandbox panel renders below the fold — the same root cause as the v0.1.2 fix in
`sandbox.js`.

**Root cause:** `_startBtnEarly.click({ force: true })` (line 273) and
`_startBtnPanel.click({ force: true })` (line 316) in `acg_restart.js` are missing
`scrollIntoViewIfNeeded()` calls. `deleteBtn` on line 339 already has
`scrollIntoViewIfNeeded()` — the pattern was established but not applied to the Start
Sandbox paths.

---

## Reproduction

```bash
bin/acg-up --no-login-prompt
# Trigger condition: first credential extraction times out → sandbox restart flow kicks in
# Expected: Start Sandbox clicked successfully
# Actual:   locator.click: Element is outside of the viewport
#           CLUSTER_FAILURE PERMANENT
```

Observed in webhook job `3bf16a41` (2026-06-05 14:04):
```
INFO: Sandbox panel open but not yet provisioned — clicking Start Sandbox directly...
ERROR: locator.click: Element is outside of the viewport
  - waiting for locator('button:has-text("Start Sandbox")').first()
```

---

## Fix

### Change 1 — `playwright/acg_restart.js`: add scrollIntoViewIfNeeded before _startBtnEarly click

**Exact old block (lines 271–274):**

```js
      console.error('INFO: Sandbox already deleted — Start Sandbox visible, skipping delete flow.');
      console.error('INFO: Clicking Start Sandbox...');
      await _startBtnEarly.click({ force: true });
      await page.waitForTimeout(3000);
```

**Exact new block:**

```js
      console.error('INFO: Sandbox already deleted — Start Sandbox visible, skipping delete flow.');
      console.error('INFO: Clicking Start Sandbox...');
      await _startBtnEarly.scrollIntoViewIfNeeded().catch(() => {});
      await _startBtnEarly.click({ force: true });
      await page.waitForTimeout(3000);
```

### Change 2 — `playwright/acg_restart.js`: add scrollIntoViewIfNeeded before _startBtnPanel click

**Exact old block (lines 315–317):**

```js
        console.error('INFO: Sandbox panel open but not yet provisioned — clicking Start Sandbox directly...');
        await _startBtnPanel.click({ force: true });
        await page.waitForTimeout(3000);
```

**Exact new block:**

```js
        console.error('INFO: Sandbox panel open but not yet provisioned — clicking Start Sandbox directly...');
        await _startBtnPanel.scrollIntoViewIfNeeded().catch(() => {});
        await _startBtnPanel.click({ force: true });
        await page.waitForTimeout(3000);
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_restart.js` | Add `scrollIntoViewIfNeeded()` before `_startBtnEarly` and `_startBtnPanel` clicks |

---

## Rules

- `node --check playwright/acg_restart.js` — must pass with zero errors
- Code change limited to `playwright/acg_restart.js`; `CHANGELOG.md`, this bug spec doc, and memory-bank updates are also expected

---

## Definition of Done

- [ ] `playwright/acg_restart.js` matches exact new blocks above
- [ ] `node --check playwright/acg_restart.js` passes
- [ ] `CHANGELOG.md` updated with fix entry under `[Unreleased]`
- [ ] Committed and pushed to `feat/v0.1.3`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg_restart): scrollIntoViewIfNeeded before Start Sandbox clicks in restart flow
```

---

## What NOT to Do

- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any code file other than `playwright/acg_restart.js` (CHANGELOG.md and memory-bank updates are expected)
- Do NOT commit to `main` — work on `feat/v0.1.3`
