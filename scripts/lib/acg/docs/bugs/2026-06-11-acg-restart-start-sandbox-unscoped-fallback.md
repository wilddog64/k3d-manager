# Bug: acg_restart.js poll loop misses Start Sandbox in detached panel overlay

**Date:** 2026-06-11
**Repo:** lib-acg
**Branch:** feat/v0.1.5
**File:** `playwright/acg_restart.js`

---

## Symptom

`acg_restart.js` throws after clicking Open Sandbox:

```
ERROR: Delete Sandbox button did not appear within 15s after Open Sandbox click.
URL: https://app.pluralsight.com/hands-on/playground/cloud-sandboxes
Buttons: ["Iris","Help","Help","L","Learn More","Open Sandbox","Learn More","Open Sandbox",
          "Learn More","Open Sandbox","Close","Start Sandbox","11"]
```

The "Start Sandbox" button IS present. The `_sandboxNotYetStarted` path should handle
this case (click Start Sandbox directly), but it never triggers.

---

## Root Cause

After `Open Sandbox` is clicked, the ACG sandbox detail panel renders as a **detached
overlay** appended to `<body>` — it is NOT nested inside the provider card DOM node.

`_findScopedButton('Start Sandbox', providerLabel, 0)` (line 314) walks up 8 ancestor
levels from each button. For a button inside the detached overlay, the ancestor chain is:

```
button → div.panel-content → div.overlay → body
```

None of these ancestors contain the provider label ('Azure'). The scoped search returns
null. `_sandboxNotYetStarted` stays false, the poll times out, and the throw fires.

The `_deleteBtnReady` path also fails for the same reason (Delete Sandbox in the panel
also sits in the detached overlay), but since the sandbox isn't running, Delete Sandbox
never appears.

---

## Fix

### Change 1 — `playwright/acg_restart.js`: add unscoped fallback in poll loop

After `_findScopedButton('Start Sandbox', _providerCardLabel, 0)` returns null, check
whether the panel is open (Close button visible) and Start Sandbox is visible globally.
Since we just clicked "Open Sandbox" for exactly one provider, one panel is open — any
visible Start Sandbox must belong to that provider.

**Exact old block (lines 314–319):**

```javascript
        _startBtnPanelScoped = await _findScopedButton(page, 'Start Sandbox', _providerCardLabel, 0);
        if (_startBtnPanelScoped) {
          _sandboxNotYetStarted = true;
          break;
        }
        await page.waitForTimeout(500).catch(() => {});
```

**Exact new block:**

```javascript
        _startBtnPanelScoped = await _findScopedButton(page, 'Start Sandbox', _providerCardLabel, 0);
        if (!_startBtnPanelScoped) {
          // Panel may render as a detached overlay — scoped ancestor walk cannot find provider
          // label. Fall back to unscoped detection: Close button visible (panel open) + Start
          // Sandbox visible means the open panel is in Start Sandbox state.
          const _panelOpen = await page.locator('button:has-text("Close")').first()
            .isVisible({ timeout: 0 }).catch(() => false);
          if (_panelOpen) {
            const _startGlobal = page.locator('button:has-text("Start Sandbox")').first();
            const _startVis = await _startGlobal.isVisible({ timeout: 0 }).catch(() => false);
            if (_startVis) _startBtnPanelScoped = _startGlobal;
          }
        }
        if (_startBtnPanelScoped) {
          _sandboxNotYetStarted = true;
          break;
        }
        await page.waitForTimeout(500).catch(() => {});
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_restart.js` | Add unscoped fallback in poll loop when Start Sandbox is in detached overlay |

---

## Rules

- `node --check playwright/acg_restart.js` must pass
- No other files touched

---

## Definition of Done

- [ ] Unscoped fallback block added after `_findScopedButton('Start Sandbox', ...)` (lines 314–319)
- [ ] Fallback checks: Close button visible (panel open) AND Start Sandbox visible globally
- [ ] If fallback succeeds, `_startBtnPanelScoped` is set and `_sandboxNotYetStarted = true` triggers
- [ ] `node --check playwright/acg_restart.js` passes
- [ ] Committed and pushed to `feat/v0.1.5`
- [ ] memory-bank updated with commit SHA and task status (in k3d-manager repo)

**Commit message (exact):**
```
fix(restart): add unscoped Start Sandbox fallback for detached panel overlay
```

---

## What NOT to Do

- Do NOT create a PR yourself — Claude handles PR creation after verifying the commit
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_restart.js`
- Do NOT commit to `main` — work on `feat/v0.1.5`
- Do NOT replace `_findScopedButton` — the fallback is additive only
