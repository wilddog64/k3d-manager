# Bug: _waitForCredentials throws when panel closes during sandbox provisioning

**Date:** 2026-06-11
**Repo:** lib-acg
**Branch:** feat/v0.1.5
**File:** `playwright/lib/sandbox.js`

---

## Symptom

`make credential-test PROVIDER=azure` (after conflict warning + AWS deletion) fails:

```
WARN: Azure panel stayed closed after reopen attempt — aborting instead of looping for 420s.
ERROR: Azure panel stayed closed after reopen attempt — aborting instead of looping for 420s.
```

The page shows "Hang tight! Your sandbox is starting... Finalizing your playground" —
the Azure sandbox IS provisioning, but the credential panel auto-closes during provisioning.

---

## Root Cause

After the conflict warning fix (`5f704d1`) deletes AWS and retries opening Azure,
`startSandbox` clicks Start Sandbox inside the Azure panel and falls through to
`_waitForCredentials`. The panel auto-closes while Azure is provisioning (ACG design —
the panel dismisses itself during sandbox startup).

`_waitForCredentials` polls for credentials. When it finds the panel is closed (Open
Sandbox button visible), it tries ONE reopen, sets `reopenAttempted = true`, then the
panel auto-closes again immediately. On the next iteration, `reopenAttempted` is `true`
→ throws immediately, even though Azure is still provisioning and will surface credentials
in the full panel once startup completes.

The fix: detect the "Hang tight" provisioning banner. While provisioning is in progress,
do not reopen and do not throw — just wait. Once provisioning completes and "Hang tight"
disappears, open the panel once to retrieve credentials.

---

## Fix

### Change 1 — `playwright/lib/sandbox.js`: check for provisioning banner before reopen/throw

**Exact old block (lines 247–258):**

```javascript
    const reopenBtn = await _findScopedButton(page, 'Open Sandbox', providerLabel, 0);
    if (reopenBtn) {
      if (reopenAttempted) {
        await _capturePageDebugState(page, providerLabel, `${providerLabel} panel stayed closed after reopen attempt — aborting instead of looping for 420s.`);
        throw new Error(`${providerLabel} panel stayed closed after reopen attempt — aborting instead of looping for 420s.`);
      }
      console.error(`INFO: ${providerLabel} panel closed — re-opening to retrieve credentials...`);
      await reopenBtn.click({ force: true }).catch(() => {});
      await page.waitForTimeout(3000);
      reopenAttempted = true;
      continue;
    }
```

**Exact new block:**

```javascript
    const reopenBtn = await _findScopedButton(page, 'Open Sandbox', providerLabel, 0);
    if (reopenBtn) {
      const provisioning = await page.evaluate(() => {
        const t = document.body ? (document.body.innerText || '') : '';
        return t.includes('Hang tight') || t.includes('Finalizing your playground');
      }).catch(() => false);
      if (provisioning) {
        console.error(`INFO: ${providerLabel} sandbox is provisioning — waiting before reopening panel...`);
        await page.waitForTimeout(5000);
        continue;
      }
      if (reopenAttempted) {
        await _capturePageDebugState(page, providerLabel, `${providerLabel} panel stayed closed after reopen attempt — aborting instead of looping for 420s.`);
        throw new Error(`${providerLabel} panel stayed closed after reopen attempt — aborting instead of looping for 420s.`);
      }
      console.error(`INFO: ${providerLabel} panel closed — re-opening to retrieve credentials...`);
      await reopenBtn.click({ force: true }).catch(() => {});
      await page.waitForTimeout(3000);
      reopenAttempted = true;
      continue;
    }
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Add provisioning banner check in `_waitForCredentials` before reopen/throw |

---

## Rules

- `node --check playwright/lib/sandbox.js` must pass
- No other files touched

---

## Definition of Done

- [ ] Provisioning check added between `_findScopedButton` result and `reopenAttempted` check
- [ ] Check uses `document.body.innerText` for both "Hang tight" and "Finalizing your playground"
- [ ] When provisioning: logs INFO, waits 5s, continues loop — does NOT reopen, does NOT throw
- [ ] When not provisioning: existing `reopenAttempted` throw logic is unchanged
- [ ] `node --check playwright/lib/sandbox.js` passes
- [ ] Committed and pushed to `feat/v0.1.5`
- [ ] memory-bank updated with commit SHA and task status (in k3d-manager repo)

**Commit message (exact):**
```
fix(sandbox): wait for provisioning banner in _waitForCredentials — panel auto-closes during Azure startup
```

---

## What NOT to Do

- Do NOT create a PR yourself — Claude handles PR creation after verifying the commit
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/lib/sandbox.js`
- Do NOT commit to `main` — work on `feat/v0.1.5`
- Do NOT remove the `reopenAttempted` guard — it still applies when provisioning is NOT in progress
- Do NOT change the `reopenAttempted` throw message text
