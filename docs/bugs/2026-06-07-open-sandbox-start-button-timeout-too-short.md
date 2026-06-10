# Bugfix: v0.1.4 — Open Sandbox → Start Sandbox step times out, Azure sandbox never starts

**Branch:** `feat/v0.1.4`
**Files:** `playwright/lib/sandbox.js`, `CHANGELOG.md`, `memory-bank/activeContext.md`, `memory-bank/progress.md`

---

## Problem

After deleting a conflicting AWS sandbox and clicking Azure's "Open Sandbox", the script
searches for the "Start Sandbox" button using `_findScopedButton(page, 'Start Sandbox', 'Azure', 5000)`.
The total window is only **8 seconds** (3s `waitForTimeout` + 5s `_findScopedButton`). If the
Azure panel takes longer than 8s to render its "Start Sandbox" button, the search returns null.

The script then falls straight through to `_waitForCredentials`, which spins up to 420s waiting
for credential inputs to populate. Because Azure's "Start Sandbox" was never clicked, credentials
never appear, and the flow times out.

**Observed symptom:**
```
INFO: AWS sandbox deleted.
INFO: Clicking Open Sandbox...
INFO: Waiting for Azure credentials to populate (up to 420s)...
```
No "Clicking Start Sandbox (Step 2)..." logged. Browser shows AWS panel (empty fields)
while script waits forever.

**Root cause (line 352):**
```javascript
const startButton2 = await _findScopedButton(page, 'Start Sandbox', providerLabel, 5000);
```
5000ms is too short. Azure's panel transition after "Open Sandbox" may take longer.

---

## Fix

### Change 1 — `playwright/lib/sandbox.js`: increase `startButton2` timeout and add fallback

**Exact old block (lines 352–363):**

```javascript
    const startButton2 = await _findScopedButton(page, 'Start Sandbox', providerLabel, 5000);
    if (startButton2) {
      const startEnabled2 = await startButton2.isEnabled({ timeout: 1000 }).catch(() => false);
      if (startEnabled2) {
        console.error('INFO: Clicking Start Sandbox (Step 2)...');
        await startButton2.scrollIntoViewIfNeeded().catch(() => {});
        await startButton2.click({ force: true });
      } else {
        console.error('INFO: Start Sandbox button is disabled — sandbox already running; waiting for credentials...');
      }
    }
    await _waitForCredentials(page, providerLabel);
```

**Exact new block:**

```javascript
    let startButton2 = await _findScopedButton(page, 'Start Sandbox', providerLabel, 30000);
    if (!startButton2) {
      console.error(`WARN: Scoped Start Sandbox not found for ${providerLabel} — trying any visible enabled Start Sandbox as fallback...`);
      const allStart = page.locator('button:has-text("Start Sandbox")');
      const count = await allStart.count().catch(() => 0);
      for (let i = 0; i < count; i++) {
        const btn = allStart.nth(i);
        const visible = await btn.isVisible({ timeout: 300 }).catch(() => false);
        const enabled = await btn.isEnabled({ timeout: 300 }).catch(() => false);
        if (visible && enabled) { startButton2 = btn; break; }
      }
    }
    if (startButton2) {
      const startEnabled2 = await startButton2.isEnabled({ timeout: 1000 }).catch(() => false);
      if (startEnabled2) {
        console.error('INFO: Clicking Start Sandbox (Step 2)...');
        await startButton2.scrollIntoViewIfNeeded().catch(() => {});
        await startButton2.click({ force: true });
      } else {
        console.error('INFO: Start Sandbox button is disabled — sandbox already running; waiting for credentials...');
      }
    } else {
      console.error(`WARN: No Start Sandbox button found for ${providerLabel} after Open Sandbox — proceeding to credential wait`);
    }
    await _waitForCredentials(page, providerLabel);
```

**Why the fallback is safe:** by the time `startButton2` fallback runs, the conflicting sandbox
has already been deleted. The only enabled "Start Sandbox" on the page should belong to the target
provider. The unscoped fallback picks the first visible+enabled one.

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Increase `startButton2` timeout to 30000ms; add fallback for any visible enabled button |
| `CHANGELOG.md` | Add `[Unreleased]` entry under `### Fixed` |
| `memory-bank/activeContext.md` | Update current status |
| `memory-bank/progress.md` | Update v0.1.4 track |

---

## Rules

- `node --check playwright/lib/sandbox.js` — zero errors
- No other files touched

---

## Definition of Done

- [ ] `startButton2` timeout changed from `5000` to `30000`
- [ ] Fallback loop added after scoped search returns null: find first visible+enabled "Start Sandbox"
- [ ] WARN log emitted when fallback triggers
- [ ] WARN log emitted when no button found even after fallback
- [ ] `make check lint test` passes (run in lib-acg repo root)
- [ ] `node --check playwright/lib/sandbox.js` passes
- [ ] `CHANGELOG.md` updated under `### Fixed`
- [ ] Committed and pushed to `feat/v0.1.4`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(sandbox): increase startButton2 timeout to 30s and add fallback after Open Sandbox click
```

---

## What NOT to Do

- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/lib/sandbox.js` (plus `CHANGELOG.md` and `memory-bank/`)
- Do NOT commit to `main` — work on `feat/v0.1.4`
- Do NOT change `_findScopedButton`, `_waitForCredentials`, `_deleteConflictingSandbox`, or any other function
- Do NOT touch `azure.js`, `acg_credentials.js`, or any provider file
