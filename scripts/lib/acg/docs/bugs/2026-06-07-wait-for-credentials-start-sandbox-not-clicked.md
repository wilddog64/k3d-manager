# Bugfix: v0.1.4 — _waitForCredentials never clicks Start Sandbox when panel is open but unstarted

**Branch:** `feat/v0.1.4`
**Files:** `playwright/lib/sandbox.js`, `CHANGELOG.md`, `memory-bank/activeContext.md`, `memory-bank/progress.md`

---

## Problem

After `startSandbox` clicks "Open Sandbox" for Azure, the 30s provider-scoped search for
"Start Sandbox" returns null (even though the button is visible). The fallback (8-level
ancestor walk with provider exclusion) also returns null — the ancestor walk reaches a shared
grid container whose `innerText` includes both "Azure Sandbox" and "AWS Sandbox" text before
finding an Azure-only node, so the exclusion check rejects every candidate.

`startSandbox` then falls through to `_waitForCredentials` without having clicked "Start Sandbox".

Inside `_waitForCredentials`:
- Credential inputs are present in the DOM (panel is open) but **empty** (sandbox not started)
- The "Start Sandbox" button is visible in the panel
- The current logic: empty inputs → skip credential check → `_findScopedButton('Open Sandbox')` →
  finds "Open Sandbox" (either still in card area, or panel auto-closed) → clicks → panel toggles
- Result: panel open/close cycle every 2s, "Start Sandbox" is never clicked, 420s timeout

**Observed log:**
```
WARN: Scoped Start Sandbox not found for Azure — trying provider-scoped fallback...
WARN: No Start Sandbox button found for Azure after Open Sandbox — proceeding to credential wait
INFO: Waiting for Azure credentials to populate (up to 420s)...
INFO: "Extend Your Session" dialog detected — clicking Extend button...
INFO: Azure panel closed — re-opening to retrieve credentials...
(repeating every ~2s for 420s)
```

**Screenshot evidence:** Azure Sandbox panel is open showing "Start Sandbox" button and four
empty credential input fields (Username, Password, Application Client ID, Secret). Script
was stuck looping without clicking "Start Sandbox".

**Root cause (lines 165–183):** `_waitForCredentials` checks for populated credentials and
re-opens a closed panel, but has no path for the case where credential inputs exist AND are
empty AND a "Start Sandbox" button is in the same panel subtree (sandbox not yet started).

---

## Fix

### Change 1 — `playwright/lib/sandbox.js`: detect and click "Start Sandbox" when panel is open but unstarted

Scope "Start Sandbox" by **proximity to credential inputs** rather than provider label text.
When credential inputs exist but are empty, walk 8 ancestors up from the first credential input
and check if a "Start Sandbox" button exists in that subtree. If yes, the panel is open and
the sandbox hasn't been started — click it. Only fall through to the re-open logic when no
Start Sandbox is detected (panel is truly closed, not in unstarted state).

**Exact old block (lines 165–183):**

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
      const panelHasStartBtn = await page.evaluate(() => {
        const inp = document.querySelector('input[aria-label="Copyable input"]');
        if (!inp) return false;
        let node = inp.parentElement;
        for (let j = 0; j < 8; j++) {
          if (!node) break;
          const btns = Array.from(node.querySelectorAll('button'));
          if (btns.some(b => (b.innerText || '').includes('Start Sandbox') && !b.disabled)) return true;
          node = node.parentElement;
        }
        return false;
      }).catch(() => false);
      if (panelHasStartBtn) {
        console.error(`INFO: ${providerLabel} panel open but sandbox not started — clicking Start Sandbox...`);
        await page.locator('button:has-text("Start Sandbox")').first().click({ force: true }).catch(() => {});
        await page.waitForTimeout(5000);
        continue;
      }
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

**Why this works:**

- **Credential input presence check** (`inputs.count() > 0`) detects that the panel is open
  (inputs are in the DOM). Combined with `value.trim().length === 0`, it confirms the panel
  is showing but the sandbox hasn't started yet.
- **`page.evaluate` proximity check** (`panelHasStartBtn`) walks 8 ancestors from the first
  credential input and searches its subtree for a "Start Sandbox" button. This is DOM-proximity
  scoping rather than provider-label scoping — the credential inputs and "Start Sandbox" button
  are siblings within the panel container, so they share a common ancestor within 3–4 levels.
  This avoids the ancestor-walk provider-exclusion failure that affected `startSandbox`.
- **Unscoped `button:has-text("Start Sandbox")`.first()** click is safe here: we only reach
  this path when `panelHasStartBtn` confirmed a "Start Sandbox" button is co-located with
  the credential inputs. The first matching button in DOM order should be the one in the open
  panel.
- **5s wait** after clicking gives the sandbox time to begin provisioning before the next
  credential check.
- **Re-open only fires when no credential inputs found** (panel truly closed, not in
  unstarted state) — prevents the toggle-close cycle.

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Add `panelHasStartBtn` check and Start Sandbox click to `_waitForCredentials` |
| `CHANGELOG.md` | Add `[Unreleased]` entry under `### Fixed` |
| `memory-bank/activeContext.md` | Update current status |
| `memory-bank/progress.md` | Update v0.1.4 track |

---

## Rules

- `node --check playwright/lib/sandbox.js` — zero errors
- No other files touched

---

## Definition of Done

- [ ] `_waitForCredentials` loop: after empty-credential check, calls `page.evaluate` to detect `panelHasStartBtn` by walking up 8 ancestors from `document.querySelector('input[aria-label="Copyable input"]')` looking for a non-disabled "Start Sandbox" button
- [ ] When `panelHasStartBtn` is true: logs `INFO: ${providerLabel} panel open but sandbox not started — clicking Start Sandbox...`, clicks `.first()` with `force: true`, waits 5000ms, continues
- [ ] Re-open ("Open Sandbox") check only reached when `inputs.count() === 0` (panel truly closed)
- [ ] `node --check playwright/lib/sandbox.js` passes
- [ ] `make check lint test` passes (run in lib-acg repo root)
- [ ] `CHANGELOG.md` updated under `### Fixed`
- [ ] Committed and pushed to `feat/v0.1.4`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(sandbox): click Start Sandbox in _waitForCredentials when panel open but unstarted
```

---

## What NOT to Do

- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/lib/sandbox.js` (plus `CHANGELOG.md` and `memory-bank/`)
- Do NOT commit to `main` — work on `feat/v0.1.4`
- Do NOT change `_findScopedButton`, `_deleteConflictingSandbox`, or any other function
- Do NOT touch `acg_credentials.js`, `acg_restart.js`, or any provider file
- Do NOT try to fix `startSandbox`'s scoped search — the `_waitForCredentials` recovery is the correct layer for this
