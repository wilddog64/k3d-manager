# Bug: _deleteConflictingSandbox can't find Azure buttons when AWS credential panel is open; _waitForCredentials falls through to reopen loop

**Date:** 2026-06-12
**Branch (lib-acg):** `feat/v0.1.7`
**File:** `playwright/lib/sandbox.js`

---

## Symptom

```
WARN: AWS panel stayed closed after 3 reopen attempts — aborting.
ERROR: AWS panel stayed closed after 3 reopen attempts — aborting.
INFO: Detached from Chrome CDP session.
ERROR: AWS panel stayed closed after 3 reopen attempts — aborting.
ERROR: Credential extraction still failing after restart.
make: *** [credential-test] Error 1
```

Azure sandbox is still running throughout. Debug screenshot (`k3dm-aws-*.png`) shows
the AWS credential panel is open with empty fields and the conflict banner visible.

---

## Root Cause (2-bug chain)

### Bug 1 — `_deleteConflictingSandbox` blocked by open AWS credential panel

When `startSandbox` runs, the AWS credential panel may already be open (left open from a
prior session or interaction). The panel is a full-screen modal — it covers the page and
hides all other provider cards including Azure's controls.

`_deleteConflictingSandbox` detects the conflict via the banner text ✅, gets
`conflictingLabel = 'Azure'`, then calls:

1. `_findScopedButton('Delete Sandbox', 'Azure', 2000)` — Azure's "Delete Sandbox" is
   **invisible** (hidden behind the AWS modal) → returns null
2. `_findScopedButton('Open Sandbox', 'Azure', 5000)` — Azure's "Open Sandbox" is also
   **invisible** → returns null
3. Logs warning "Could not find Open Sandbox for conflicting Azure sandbox — proceeding anyway"
4. Returns **without deleting Azure**

### Bug 2 — `_waitForCredentials` falls through to `reopenBtn` when panel is already open

After `_deleteConflictingSandbox` fails (Azure still running), `startSandbox` falls
through to `_waitForCredentials`. The AWS credential panel is open (inputCount=4, all
empty). The Pluralsight UI keeps "Open Sandbox" visible on the card header even when the
credential panel is expanded — so `_findScopedButton('Open Sandbox', 'AWS', 0)` finds it.

In `_waitForCredentials`, when `inputCount > 0` AND `panelStartBtn` is null (Start Sandbox
disabled due to conflict), the code falls through the `if (inputCount > 0)` block at line
282 directly to the `reopenBtn` check (line 283). Each click on the "Open Sandbox" header
button toggles the panel. Credentials never fill (Azure still blocking). After 3 attempts:
"panel stayed closed" error.

---

## Fix

### Change 1 — `_deleteConflictingSandbox`: close target panel before looking for conflicting provider buttons

After detecting `conflictingLabel` but before the `_findScopedButton` calls, dismiss any
open credential panel for the target provider. This closes the AWS modal and makes the
full page (including Azure's provider card) visible.

**Exact old block (lines 401–405):**

```js
  if (!conflictingLabel) return;

  console.error(`INFO: Running ${conflictingLabel} sandbox detected — deleting before starting ${targetLabel}...`);

  let deleteBtn = await _findScopedButton(page, 'Delete Sandbox', conflictingLabel, 2000);
```

**Exact new block:**

```js
  if (!conflictingLabel) return;

  console.error(`INFO: Running ${conflictingLabel} sandbox detected — deleting before starting ${targetLabel}...`);
  await _closeOpenPanel(page, targetLabel);

  let deleteBtn = await _findScopedButton(page, 'Delete Sandbox', conflictingLabel, 2000);
```

---

### Change 2 — `_waitForCredentials`: prevent fall-through from `inputCount > 0` to `reopenBtn` check

When `inputCount > 0` (credential inputs are visible) and `panelStartBtn` is null, add an
explicit `continue` at the end of the `if (inputCount > 0)` block. This prevents entering
the "reopen" path when the panel is already showing inputs.

**Exact old block (lines 276–283):**

```js
      if (panelStartBtn) {
        console.error(`INFO: ${providerLabel} panel open but sandbox not started — clicking Start Sandbox...`);
        await panelStartBtn.click({ force: true }).catch(() => {});
        await page.waitForTimeout(5000);
        continue;
      }
    }
    const reopenBtn = await _findScopedButton(page, 'Open Sandbox', providerLabel, 0);
```

**Exact new block:**

```js
      if (panelStartBtn) {
        console.error(`INFO: ${providerLabel} panel open but sandbox not started — clicking Start Sandbox...`);
        await panelStartBtn.click({ force: true }).catch(() => {});
        await page.waitForTimeout(5000);
        continue;
      }
      await page.waitForTimeout(2000);
      continue;
    }
    const reopenBtn = await _findScopedButton(page, 'Open Sandbox', providerLabel, 0);
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Change 1: close target panel before looking for conflicting buttons; Change 2: prevent fall-through in credential wait |

---

## Rules

- `node --check playwright/lib/sandbox.js` — must pass
- No other files touched

---

## Before You Start

- Repo: `lib-acg`
- Branch: `feat/v0.1.7`
- Run: `git pull origin feat/v0.1.7`
- Read: `playwright/lib/sandbox.js` in full
- Confirm:
  - lines 401–405 match Change 1 old block exactly
  - lines 276–283 match Change 2 old block exactly

---

## Definition of Done

- [ ] Change 1: `await _closeOpenPanel(page, targetLabel);` inserted between the
  `console.error(... Running ${conflictingLabel} ...)` line and
  `let deleteBtn = await _findScopedButton(...)` line
- [ ] Change 2: `await page.waitForTimeout(2000); continue;` inserted between the
  closing `}` of `if (panelStartBtn)` and the closing `}` of `if (inputCount > 0)`
- [ ] `node --check playwright/lib/sandbox.js` passes
- [ ] No files other than `playwright/lib/sandbox.js` touched
- [ ] Committed and pushed to `feat/v0.1.7`
- [ ] memory-bank in k3d-manager updated with lib-acg commit SHA and task status

**Commit message (exact):**
```
fix(sandbox): close target panel before conflict deletion; prevent reopen fall-through in credential wait
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/lib/sandbox.js`
- Do NOT commit to `main` — work on `feat/v0.1.7` in lib-acg
- Do NOT remove the `await page.waitForTimeout(2000)` before `continue` in Change 2 — the loop needs the wait
- Do NOT add the close call after `if (!conflictingLabel) return;` is already in the file — verify the line matches exactly before editing
