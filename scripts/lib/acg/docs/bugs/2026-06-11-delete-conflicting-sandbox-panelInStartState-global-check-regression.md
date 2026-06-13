# Bug: _deleteConflictingSandbox panelInStartState global check — bidirectional regression

**Date:** 2026-06-11
**Repo:** lib-acg
**Branch:** feat/v0.1.5
**File:** `playwright/lib/sandbox.js`
**Supersedes:** `2026-06-11-delete-conflicting-sandbox-false-positive-start-state.md` (fix `488b558` did not resolve the regression)

---

## Symptom

Switching between any two providers (AWS→Azure or Azure→AWS) fails to delete the
conflicting sandbox. The conflicting sandbox is never deleted, and `startSandbox`
loops attempting to start the target provider while the conflict remains.

---

## Root Cause

`_deleteConflictingSandbox` is called **before** any attempt to start the target
sandbox. The conflict warning ("You may have only one active sandbox at a time…")
only appears **after** clicking "Start Sandbox" for the target provider while a
conflicting sandbox is running.

Prior fix `488b558` added a `conflictWarningActive` guard intended to suppress the
`panelInStartState` heuristic when the conflict warning is visible. However, since
`_deleteConflictingSandbox` is called before the target Start Sandbox click,
**the conflict warning is never on the page at call time**.

Result: `conflictWarningActive` is always `false` → `panelInStartState` always runs.
`panelInStartState` is a global DOM query that finds the TARGET provider's
"Start Sandbox" button (always present when we're about to start it) plus any visible
credential inputs → returns `true` → the function closes a non-existent panel and
returns without deleting the conflicting sandbox.

The heuristic is unfixable as a global DOM query because the target provider's own
buttons are indistinguishable from the conflicting provider's buttons at the global
document level.

---

## Why the Downstream Logic Already Handles "Not Running"

The deletion flow after `panelInStartState` already covers all cases correctly:

```
_findScopedButton('Delete Sandbox', conflictingLabel, 2000)  → null if not running
_findScopedButton('Open Sandbox',  conflictingLabel, 5000)  → null if not running
→ WARN: Could not find Open Sandbox — proceeding anyway
→ return  ✓
```

If the conflicting sandbox is not running: neither scoped button is found → function
returns without deleting. No additional heuristic is needed.

If the conflicting sandbox IS running: Delete Sandbox or Open Sandbox is found and
deletion proceeds correctly.

---

## Fix

Remove both the `conflictWarningActive` block and the `panelInStartState` block
introduced by `488b558`. Leave only the `if (!conflictingLabel) return;` guard
followed directly by the delete log and `_findScopedButton` calls.

### Change 1 — `playwright/lib/sandbox.js`: remove panelInStartState and conflictWarningActive blocks

**Exact old block (lines 346–376):**

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

  console.error(`INFO: Running ${conflictingLabel} sandbox detected — deleting before starting ${targetLabel}...`);
```

**Exact new block:**

```javascript
  if (!conflictingLabel) return;

  console.error(`INFO: Running ${conflictingLabel} sandbox detected — deleting before starting ${targetLabel}...`);
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Remove `conflictWarningActive` and `panelInStartState` blocks (lines 347–375) |

---

## Rules

- `node --check playwright/lib/sandbox.js` must pass
- No other files touched

---

## Definition of Done

- [ ] `conflictWarningActive` block removed (lines 348–357)
- [ ] `panelInStartState` block removed (lines 359–375)
- [ ] `if (!conflictingLabel) return;` and `console.error(...)` delete log remain intact
- [ ] `node --check playwright/lib/sandbox.js` passes
- [ ] Committed and pushed to `feat/v0.1.5`
- [ ] memory-bank updated with commit SHA and task status (in k3d-manager repo)

**Commit message (exact):**
```
fix(sandbox): remove panelInStartState heuristic — global DOM check causes bidirectional regression
```

---

## What NOT to Do

- Do NOT create a PR yourself — Claude handles PR creation after verifying the commit
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/lib/sandbox.js`
- Do NOT commit to `main` — work on `feat/v0.1.5`
- Do NOT add a replacement heuristic — the scoped `_findScopedButton` calls already handle "not running" correctly
