# Bug: startSandbox conflict warning retry calls broken _deleteConflictingSandbox detection

**Date:** 2026-06-11
**Repo:** lib-acg
**Branch:** feat/v0.1.5
**File:** `playwright/lib/sandbox.js`

---

## Symptom

`make credential-test PROVIDER=azure` (while AWS is running) fails. The Azure panel opens
and shows the conflict warning banner:

> "You may have only one active sandbox at a time. In order to start an Azure Sandbox,
> you must first shut down your current AWS sandbox."

The script does not delete AWS and eventually throws "Azure panel stayed closed after
reopen attempt."

---

## Root Cause

`_deleteConflictingSandbox` detects conflicting sandboxes by looking for a DOM element
that contains BOTH "Auto Shutdown" AND the conflicting provider keyword (e.g. "AWS").
The "Auto Shutdown" banner is a **page-level element** — it is never nested inside any
individual provider card. No element ever contains "Auto Shutdown" AND "AWS" without
also containing all other provider names. The detection always returns `null`.

`startSandbox` calls `_deleteConflictingSandbox` before opening the target panel — it
returns without deleting anything. After clicking Open Sandbox, the conflict warning
appears. The retry block at lines 476–484 calls `_deleteConflictingSandbox` again — same
broken detection, same null result. AWS is never deleted.

The conflict warning text **names the conflicting provider directly**: "you must first shut
down your current **AWS** sandbox." This is the authoritative source.

---

## Fix

Replace the broken `_deleteConflictingSandbox` retry call in the conflict warning block
with a direct delete flow that parses the conflicting provider name from the warning text.

### Change 1 — `playwright/lib/sandbox.js`: parse and delete conflicting provider from warning text

**Exact old block (lines 472–484):**

```javascript
    const conflictWarning = await page.evaluate(() =>
      Array.from(document.querySelectorAll('*'))
        .some(el => (el.innerText || '').includes('You may have only one active sandbox at a time'))
    ).catch(() => false);
    if (conflictWarning) {
      console.error('WARN: Conflict warning still visible after Open Sandbox — retrying conflict deletion...');
      await _deleteConflictingSandbox(page, provider);
      const retryOpen = await _findScopedButton(page, 'Open Sandbox', providerLabel, 10000);
      if (retryOpen) {
        await retryOpen.click({ force: true });
        await page.waitForTimeout(3000);
      }
    }
```

**Exact new block:**

```javascript
    const conflictWarningText = await page.evaluate(() => {
      const el = Array.from(document.querySelectorAll('*'))
        .find(el => (el.innerText || '').includes('You may have only one active sandbox at a time'));
      return el ? (el.innerText || '') : '';
    }).catch(() => '');
    if (conflictWarningText) {
      const _conflictMatch = conflictWarningText.match(/shut down your current ([A-Za-z ]+?) sandbox/i);
      const _conflictingProvider = _conflictMatch ? _conflictMatch[1].trim() : null;
      console.error(`WARN: Conflict warning detected — conflicting provider: ${_conflictingProvider || 'unknown'}`);
      await _closeOpenPanel(page, providerLabel);
      if (_conflictingProvider) {
        let _conflictDeleteBtn = await _findScopedButton(page, 'Delete Sandbox', _conflictingProvider, 2000);
        if (!_conflictDeleteBtn) {
          const _conflictOpenBtn = await _findScopedButton(page, 'Open Sandbox', _conflictingProvider, 5000);
          if (_conflictOpenBtn) {
            await _conflictOpenBtn.click({ force: true });
            _conflictDeleteBtn = await _findScopedButton(page, 'Delete Sandbox', _conflictingProvider, 15000);
          }
        }
        if (_conflictDeleteBtn) {
          await _conflictDeleteBtn.scrollIntoViewIfNeeded().catch(() => {});
          await _conflictDeleteBtn.click({ force: true });
          await page.waitForTimeout(1500);
          const _conflictConfirm = page.locator('[role="alertdialog"] button', { hasText: /delete sandbox/i });
          if (await _conflictConfirm.isVisible({ timeout: 3000 }).catch(() => false)) {
            await _conflictConfirm.click({ force: true });
          }
          console.error(`INFO: Waiting for ${_conflictingProvider} sandbox deletion (up to 180s)...`);
          await _findScopedButton(page, 'Start Sandbox', _conflictingProvider, 180000);
          await _closeOpenPanel(page, _conflictingProvider);
        } else {
          console.error(`WARN: Could not find Delete Sandbox for ${_conflictingProvider} — proceeding anyway`);
        }
      }
      const retryOpen = await _findScopedButton(page, 'Open Sandbox', providerLabel, 10000);
      if (retryOpen) {
        await retryOpen.click({ force: true });
        await page.waitForTimeout(3000);
      }
    }
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Replace broken `_deleteConflictingSandbox` retry with direct delete using warning text |

---

## Rules

- `node --check playwright/lib/sandbox.js` must pass
- No other files touched

---

## Definition of Done

- [ ] `conflictWarning` boolean replaced with `conflictWarningText` string (from `find` not `some`)
- [ ] Conflicting provider name parsed with regex `shut down your current ([A-Za-z ]+?) sandbox`
- [ ] Target panel closed before deleting conflicting sandbox (`_closeOpenPanel`)
- [ ] Delete flow: `_findScopedButton('Delete Sandbox')` → if null → open panel → find Delete → click → confirm dialog → wait 180s for Start Sandbox → close panel
- [ ] Retry open target panel after deletion
- [ ] `node --check playwright/lib/sandbox.js` passes
- [ ] Committed and pushed to `feat/v0.1.5`
- [ ] memory-bank updated with commit SHA and task status (in k3d-manager repo)

**Commit message (exact):**
```
fix(sandbox): parse conflicting provider from warning text — broken Auto Shutdown detection never found AWS
```

---

## What NOT to Do

- Do NOT create a PR yourself — Claude handles PR creation after verifying the commit
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/lib/sandbox.js`
- Do NOT commit to `main` — work on `feat/v0.1.5`
- Do NOT modify `_deleteConflictingSandbox` — only the conflict warning retry block in `startSandbox`
