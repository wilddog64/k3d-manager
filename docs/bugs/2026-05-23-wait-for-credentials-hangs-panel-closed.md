# Bug: acg_credentials — `_waitForCredentials` hangs 420s — Open Sandbox panel closed by dialog dismiss

**Branch (lib-acg):** `fix/next-improvements-5`
**File:** `playwright/acg_credentials.js`

---

## Problem

After `openButton.click({ force: true })`, the background watcher dismisses the
"Extend Your Session" dialog during the 3 s panel-open animation. The DOM click that
dismisses the dialog can propagate an event that collapses the slide-over panel, causing
`openButton` to become visible again. `_waitForCredentials` does not detect this — it polls
for credential inputs for the full 420 s while the panel is closed and no inputs exist.

```
INFO: Clicking Open Sandbox...
INFO: "Extend Your Session" dialog detected — clicking Cancel via DOM...
INFO: Waiting for credentials to populate (up to 420s)...
[hangs > 5 minutes]
```

**Root cause:** `_waitForCredentials` (line 468) only checks for (1) the "Extend Your
Session" modal and (2) credential input values. It never checks whether the panel is still
open. When the panel closes, `openButton` becomes visible again — a detectable signal that
`_waitForCredentials` currently ignores.

---

## Fix

### Change — `playwright/acg_credentials.js`: detect panel-closed inside `_waitForCredentials`

Add a panel-closed check immediately after the dialog check and before the credential input
check. If `openButton` is visible, the panel has closed — dismiss any dialog and re-click.

**Exact old block (lines 488–499 inside `_waitForCredentials`):**

```javascript
          const inputs = page.locator('input[aria-label="Copyable input"]');
          if (await inputs.count() > 0) {
            let value = await inputs.first().inputValue().catch(() => '');
            if (!value.trim()) {
              value = await inputs.first().evaluate(el => el.value || '').catch(() => '');
            }
            if (value.trim().length > 0) {
              return;
            }
          }
          await page.waitForTimeout(2000);
```

**Exact new block:**

```javascript
          // If Open Sandbox button reappeared, the panel closed — re-open it
          const _panelClosed = await openButton.isVisible({ timeout: 500 }).catch(() => false);
          if (_panelClosed) {
            console.error('INFO: Open Sandbox panel closed — re-dismissing dialog and re-clicking...');
            await _dismissExtendYourSessionDialog();
            await openButton.click({ force: true }).catch(() => {});
            await page.waitForTimeout(3000);
            continue;
          }
          const inputs = page.locator('input[aria-label="Copyable input"]');
          if (await inputs.count() > 0) {
            let value = await inputs.first().inputValue().catch(() => '');
            if (!value.trim()) {
              value = await inputs.first().evaluate(el => el.value || '').catch(() => '');
            }
            if (value.trim().length > 0) {
              return;
            }
          }
          await page.waitForTimeout(2000);
```

**Why:** `openButton` visible = panel is not open. Re-dismissing before re-clicking ensures
no dialog blocks the re-click. The 3 s wait after re-click matches the existing panel-open
wait. The `continue` skips the 2 s tail sleep and starts the next poll iteration immediately.

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_credentials.js` | Add 6-line panel-closed check inside `_waitForCredentials` while loop |

---

## Rules

- `node --check playwright/acg_credentials.js` must pass
- Code change limited to the listed file(s); CHANGELOG and memory-bank updates may also be required

---

## Definition of Done

- [ ] 6-line panel-closed block inserted before `const inputs = ...` inside `_waitForCredentials`
- [ ] No other functions or files modified
- [ ] `node --check playwright/acg_credentials.js` passes
- [ ] Committed and pushed to `fix/next-improvements-5` on lib-acg
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-credentials): re-open panel inside waitForCredentials when Open Sandbox button reappears
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_credentials.js`
- Do NOT commit to `main`
- Do NOT change any other function in the file
