# Bug: _deleteConflictingSandbox skips deletion — panelInStartState false positive

**Date:** 2026-06-11
**Repo:** lib-acg
**Branch:** feat/v0.1.5
**File:** `playwright/lib/sandbox.js`

---

## Symptom

Switching from `PROVIDER=azure` to `PROVIDER=aws` (or any provider switch with an active
conflicting sandbox) loops forever:

```
INFO: AWS panel open but sandbox not started — clicking Start Sandbox...
INFO: AWS panel open but sandbox not started — clicking Start Sandbox...
...
```

ACG shows: "You may have only one active sandbox at a time. In order to start an AWS
Sandbox, you must first shut down your current AZURE sandbox."

The Azure sandbox is never deleted.

---

## Root Cause

`_deleteConflictingSandbox` detects `conflictingLabel = 'Azure'` correctly, then runs
`panelInStartState` (lines 350–356) to decide whether Azure is "not running" and can be
skipped. But `panelInStartState` queries buttons and inputs **globally**, not scoped to
the Azure card:

```javascript
const hasStart = btns.some(b => (b.innerText || '').trim() === 'Start Sandbox' && !b.disabled);
const hasDelete = btns.some(b => (b.innerText || '').includes('Delete Sandbox'));
const inputs = document.querySelectorAll('input[aria-label="Copyable input"]');
return hasStart && !hasDelete && inputs.length > 0;
```

When AWS panel is open (showing Start Sandbox + empty inputs) and Azure panel is closed
(no Delete button visible), this returns `true` — falsely concluding Azure is in "not
running / Start Sandbox state". The function closes the already-closed Azure panel and
returns without deleting it.

**Root cause:** The conflict warning text on the page ("you must first shut down your
current AZURE sandbox") is authoritative — if it's present, the conflicting sandbox IS
running. The `panelInStartState` heuristic must not override it.

---

## Fix

### Change 1 — `playwright/lib/sandbox.js`: skip panelInStartState when conflict warning is active

Add a conflict-warning check immediately before `panelInStartState`. If ACG's warning
names the conflicting provider, bypass the heuristic and go straight to deletion.

**Exact old block (lines 347–362):**

```javascript
  if (!conflictingLabel) return;

  // If the conflicting panel is already open in "Start Sandbox" state (not running —
  // no Delete Sandbox button), just close it and return. Nothing to delete.
  const panelInStartState = await page.evaluate(() => {
    const btns = Array.from(document.querySelectorAll('button'));
    const hasStart = btns.some(b => (b.innerText || '').trim() === 'Start Sandbox' && !b.disabled);
    const hasDelete = btns.some(b => (b.innerText || '').includes('Delete Sandbox'));
    const inputs = document.querySelectorAll('input[aria-label="Copyable input"]');
    return hasStart && !hasDelete && inputs.length > 0;
  }).catch(() => false);

  if (panelInStartState) {
    console.error(`INFO: ${conflictingLabel} panel open in Start Sandbox state (not running) — closing panel...`);
    await _closeOpenPanel(page, conflictingLabel);
    return;
  }
```

**Exact new block:**

```javascript
  if (!conflictingLabel) return;

  // If ACG shows the "only one active sandbox" warning naming the conflicting provider,
  // the sandbox IS running — skip the Start Sandbox state heuristic and delete.
  const conflictWarningActive = await page.evaluate((cLabel) => {
    return Array.from(document.querySelectorAll('*'))
      .some(el => {
        const t = el.innerText || '';
        return t.includes('You may have only one active sandbox at a time') &&
               t.toLowerCase().includes(cLabel.toLowerCase());
      });
  }, conflictingLabel).catch(() => false);

  if (!conflictWarningActive) {
    // Only apply "not running" heuristic when there is no explicit conflict warning.
    const panelInStartState = await page.evaluate(() => {
      const btns = Array.from(document.querySelectorAll('button'));
      const hasStart = btns.some(b => (b.innerText || '').trim() === 'Start Sandbox' && !b.disabled);
      const hasDelete = btns.some(b => (b.innerText || '').includes('Delete Sandbox'));
      const inputs = document.querySelectorAll('input[aria-label="Copyable input"]');
      return hasStart && !hasDelete && inputs.length > 0;
    }).catch(() => false);

    if (panelInStartState) {
      console.error(`INFO: ${conflictingLabel} panel open in Start Sandbox state (not running) — closing panel...`);
      await _closeOpenPanel(page, conflictingLabel);
      return;
    }
  }
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Wrap `panelInStartState` check inside `if (!conflictWarningActive)` guard |

---

## Rules

- `node --check playwright/lib/sandbox.js` must pass
- No other files touched

---

## Definition of Done

- [ ] `conflictWarningActive` check added before `panelInStartState`
- [ ] `panelInStartState` block is nested inside `if (!conflictWarningActive)`
- [ ] `node --check playwright/lib/sandbox.js` passes
- [ ] Committed and pushed to `feat/v0.1.5`
- [ ] memory-bank updated with commit SHA and task status (in k3d-manager repo)

**Commit message (exact):**
```
fix(sandbox): skip panelInStartState heuristic when ACG conflict warning is active
```

---

## What NOT to Do

- Do NOT create a PR yourself — Claude handles PR creation after verifying the commit
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/lib/sandbox.js`
- Do NOT commit to `main` — work on `feat/v0.1.5`
