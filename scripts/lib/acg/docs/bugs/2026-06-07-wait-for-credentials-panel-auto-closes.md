# Bugfix: v0.1.4 — _waitForCredentials doesn't re-open panel when it auto-closes

**Branch:** `feat/v0.1.4`
**Files:** `playwright/lib/sandbox.js`, `CHANGELOG.md`, `memory-bank/activeContext.md`, `memory-bank/progress.md`

---

## Problem

After clicking Azure's "Open Sandbox", the script searches for "Start Sandbox" for 30s. For
an already-running Azure sandbox the credentials panel opens immediately — there is no "Start
Sandbox" button. The 30s search correctly times out and `_waitForCredentials` is entered.

However, the Azure panel auto-closes during those 30s of inactivity. By the time
`_waitForCredentials` runs, the panel is gone and there are no credential inputs in the DOM.
`_waitForCredentials` has no re-open logic, so it spins for the full 420s and times out.

**Observed log:**
```
INFO: AWS sandbox deleted.
INFO: Clicking Open Sandbox...
WARN: Scoped Start Sandbox not found for Azure — trying provider-scoped fallback...
WARN: No Start Sandbox button found for Azure after Open Sandbox — proceeding to credential wait
INFO: Waiting for Azure credentials to populate (up to 420s)...
INFO: "Extend Your Session" dialog detected — clicking Extend button...
WARN: "Extend Your Session" dialog still visible — credentials populate on either Cancel or Extend; continuing
```
Screenshot taken during the 420s wait confirms both sandboxes are in card view ("Open Sandbox"
buttons visible) — the Azure panel is closed.

**Root cause (lines 165–178):** `_waitForCredentials` only checks for credential inputs and
dismisses the Extend dialog. It has no logic to detect that the provider's panel closed (i.e.
"Open Sandbox" became visible again) and re-open it.

**Historical note:** the old `acg_credentials.js` `_waitForCredentials` had this re-open
logic (commit `7d04391`). It was lost when the function was centralized to `sandbox.js`.

---

## Fix

### Change 1 — `playwright/lib/sandbox.js`: add panel re-open check to `_waitForCredentials`

**Exact old block (lines 165–178):**

```javascript
async function _waitForCredentials(page, providerLabel) {
  console.error(`INFO: Waiting for ${providerLabel} credentials to populate (up to 420s)...`);
  const deadline = Date.now() + 420000;
  while (Date.now() < deadline) {
    await _dismissExtendYourSessionDialog(page);
    const inputs = page.locator('input[aria-label="Copyable input"]');
    if (await inputs.count() > 0) {
      const value = await inputs.first().inputValue().catch(() => '');
      if (value.trim().length > 0) return;
    }
    await page.waitForTimeout(2000);
  }
  throw new Error(`Timed out after 420000ms waiting for ${providerLabel} credentials to populate.`);
}
```

**Exact new block:**

```javascript
async function _waitForCredentials(page, providerLabel) {
  console.error(`INFO: Waiting for ${providerLabel} credentials to populate (up to 420s)...`);
  const deadline = Date.now() + 420000;
  while (Date.now() < deadline) {
    await _dismissExtendYourSessionDialog(page);
    const inputs = page.locator('input[aria-label="Copyable input"]');
    if (await inputs.count() > 0) {
      const value = await inputs.first().inputValue().catch(() => '');
      if (value.trim().length > 0) return;
    }
    const reopenBtn = await _findScopedButton(page, 'Open Sandbox', providerLabel, 0);
    if (reopenBtn) {
      console.error(`INFO: ${providerLabel} panel closed — re-opening to retrieve credentials...`);
      await reopenBtn.click({ force: true }).catch(() => {});
    }
    await page.waitForTimeout(2000);
  }
  throw new Error(`Timed out after 420000ms waiting for ${providerLabel} credentials to populate.`);
}
```

**Why this works:** `_findScopedButton` with `timeoutMs = 0` does a single immediate DOM check
(no sleep). If the provider-scoped "Open Sandbox" button is visible — meaning the panel has
collapsed back to card view — the button is clicked to re-open it. Credentials are then
re-exposed in the next 2s tick. If the panel is already open (no "Open Sandbox" visible),
`_findScopedButton` returns null and the re-open step is skipped.

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Add `_findScopedButton` re-open check to `_waitForCredentials` |
| `CHANGELOG.md` | Add `[Unreleased]` entry under `### Fixed` |
| `memory-bank/activeContext.md` | Update current status |
| `memory-bank/progress.md` | Update v0.1.4 track |

---

## Rules

- `node --check playwright/lib/sandbox.js` — zero errors
- No other files touched

---

## Definition of Done

- [ ] `_waitForCredentials` loop body: after the credential-input check, calls `_findScopedButton(page, 'Open Sandbox', providerLabel, 0)` and clicks the result with `force: true` when non-null
- [ ] Log `INFO: ${providerLabel} panel closed — re-opening to retrieve credentials...` emitted when re-open fires
- [ ] `node --check playwright/lib/sandbox.js` passes
- [ ] `make check lint test` passes (run in lib-acg repo root)
- [ ] `CHANGELOG.md` updated under `### Fixed`
- [ ] Committed and pushed to `feat/v0.1.4`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(sandbox): re-open provider panel in _waitForCredentials when it auto-closes
```

---

## What NOT to Do

- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/lib/sandbox.js` (plus `CHANGELOG.md` and `memory-bank/`)
- Do NOT commit to `main` — work on `feat/v0.1.4`
- Do NOT change `_findScopedButton`, `_deleteConflictingSandbox`, or any other function
- Do NOT add "Start Sandbox" click logic inside `_waitForCredentials` — that path is handled by `startSandbox` before `_waitForCredentials` is called
- Do NOT touch `acg_credentials.js`, `acg_restart.js`, or any provider file
