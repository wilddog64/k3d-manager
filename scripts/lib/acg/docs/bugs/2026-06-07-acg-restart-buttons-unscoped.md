# Bugfix: v0.1.4 — sandbox cycling: startButton2 fallback unscoped + acg_restart.js button lookups unscoped

**Branch:** `feat/v0.1.4`
**Files:** `playwright/lib/sandbox.js`, `playwright/acg_restart.js`, `CHANGELOG.md`, `memory-bank/activeContext.md`, `memory-bank/progress.md`

---

## Problem

Two unscoped button lookups combine to cause a sandbox cycling loop observed in live tests:

### Bug A — `sandbox.js` startButton2 fallback is unscoped

After deleting the conflicting sandbox (e.g. AWS) and clicking the target provider's "Open
Sandbox", `startSandbox` searches for the provider-scoped "Start Sandbox" with a 30s timeout.
If that returns null, the fallback loop at lines 353–363 iterates all visible+enabled "Start
Sandbox" buttons with **no provider filter**.

At that moment the page shows TWO "Start Sandbox" buttons simultaneously:
1. The deleted sandbox's card (e.g. AWS — deleted, showing "Start Sandbox" to re-provision)
2. The target provider's panel (e.g. Azure — just opened, waiting to be started)

The fallback picks DOM-first, which is typically the wrong provider (AWS card is above Azure).
The wrong sandbox starts; `_waitForCredentials` sees its credentials; the target provider's
extractor times out. `acg_restart.js` then runs on the failed state.

### Bug B — `acg_restart.js` has unscoped button lookups and missing exclusion check

`acg_restart.js` has its own copy of `_findScopedButton` (lines 96–119). The exclusion check
added to `sandbox.js`'s copy in `654f319` was never applied here. Without it, a shared
ancestor whose `innerText` includes all provider labels can match the wrong provider's button.

Three additional button lookups are unscoped plain locators:
- `deleteBtn` (line 283): `.first()` — may delete the wrong provider's sandbox
- `openBtn` (line 286): `.first()` — may open the wrong provider's panel
- `_startBtnPanel` (line 302): `.first()` — in the `_sandboxNotYetStarted` path, may start the wrong provider

**Symptom from live test log:**
```
WARN: Scoped Start Sandbox not found for Azure — trying any visible enabled Start Sandbox as fallback...
INFO: Clicking Start Sandbox (Step 2)...
INFO: Waiting for Azure credentials to populate (up to 420s)...
ERROR: page.waitForFunction: Timeout 30000ms exceeded
...
INFO: Running AWS sandbox detected — deleting before starting Azure...
```
AWS keeps re-appearing after deletion because the fallback restarted it in the previous cycle.

---

## Fix

### Change 1 — `playwright/lib/sandbox.js`: add provider exclusion check to startButton2 fallback

**Exact old block (lines 352–363):**

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
```

**Exact new block:**

```javascript
    let startButton2 = await _findScopedButton(page, 'Start Sandbox', providerLabel, 30000);
    if (!startButton2) {
      console.error(`WARN: Scoped Start Sandbox not found for ${providerLabel} — trying provider-scoped fallback...`);
      const allStart = page.locator('button:has-text("Start Sandbox")');
      const count = await allStart.count().catch(() => 0);
      const _fbOthers = ['AWS', 'Google Cloud', 'GCP', 'Azure'].filter(p => !new RegExp(p, 'i').test(providerLabel));
      for (let i = 0; i < count; i++) {
        const btn = allStart.nth(i);
        const visible = await btn.isVisible({ timeout: 300 }).catch(() => false);
        const enabled = await btn.isEnabled({ timeout: 300 }).catch(() => false);
        if (!visible || !enabled) continue;
        const inTargetCard = await btn.evaluate((el, [pLabel, others]) => {
          let node = el.parentElement;
          for (let j = 0; j < 8; j++) {
            if (!node) break;
            const t = node.innerText || '';
            if (new RegExp(pLabel, 'i').test(t) && !others.some(p => t.includes(p))) return true;
            node = node.parentElement;
          }
          return false;
        }, [providerLabel, _fbOthers]).catch(() => false);
        if (inTargetCard) { startButton2 = btn; break; }
      }
    }
```

---

### Change 2 — `playwright/acg_restart.js`: add exclusion check to `_findScopedButton`

**Exact old block (lines 96–119):**

```javascript
async function _findScopedButton(page, buttonText, providerLabel, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() <= deadline) {
    const allBtns = page.locator(`button:has-text("${buttonText}")`);
    const count = await allBtns.count().catch(() => 0);
    for (let i = 0; i < count; i++) {
      const btn = allBtns.nth(i);
      const visible = await btn.isVisible({ timeout: 300 }).catch(() => false);
      if (!visible) continue;
      const inCard = await btn.evaluate((el, label) => {
        let node = el.parentElement;
        for (let j = 0; j < 8; j++) {
          if (!node) break;
          if (new RegExp(label, 'i').test(node.innerText || '')) return true;
          node = node.parentElement;
        }
        return false;
      }, providerLabel).catch(() => false);
      if (inCard) return btn;
    }
    if (Date.now() < deadline) await page.waitForTimeout(500);
  }
  return null;
}
```

**Exact new block:**

```javascript
async function _findScopedButton(page, buttonText, providerLabel, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() <= deadline) {
    const allBtns = page.locator(`button:has-text("${buttonText}")`);
    const count = await allBtns.count().catch(() => 0);
    for (let i = 0; i < count; i++) {
      const btn = allBtns.nth(i);
      const visible = await btn.isVisible({ timeout: 300 }).catch(() => false);
      if (!visible) continue;
      const inCard = await btn.evaluate((el, label) => {
        const others = ['AWS', 'Google Cloud', 'GCP', 'Azure'].filter(
          p => !new RegExp(p, 'i').test(label)
        );
        let node = el.parentElement;
        for (let j = 0; j < 8; j++) {
          if (!node) break;
          const t = node.innerText || '';
          if (new RegExp(label, 'i').test(t) && !others.some(p => t.includes(p))) return true;
          node = node.parentElement;
        }
        return false;
      }, providerLabel).catch(() => false);
      if (inCard) return btn;
    }
    if (Date.now() < deadline) await page.waitForTimeout(500);
  }
  return null;
}
```

---

### Change 3 — `playwright/acg_restart.js`: scope `deleteBtn` initial check and `openBtn`

**Exact old block (lines 282–296):**

```javascript
    // If Delete Sandbox is not immediately visible, click Open Sandbox to reveal the panel
    const deleteBtn = page.locator('button:has-text("Delete Sandbox")').first();
    if (!await deleteBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Delete Sandbox not visible — clicking Open Sandbox to reveal panel...');
      const openBtn = page.locator('button:has-text("Open Sandbox")').first();
      if (!await openBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
        const url = page.url();
        const btns = await page.evaluate(() =>
          Array.from(document.querySelectorAll('button'))
            .map(b => (b.innerText || b.textContent || '').trim())
            .filter(t => t.length > 0)
        ).catch(() => []);
        throw new Error(`Neither Delete Sandbox nor Open Sandbox visible. URL: ${url} | Buttons: ${JSON.stringify(btns)}`);
      }
      await openBtn.click({ force: true });
```

**Exact new block:**

```javascript
    // If Delete Sandbox is not immediately visible, click Open Sandbox to reveal the panel
    let deleteBtn = await _findScopedButton(page, 'Delete Sandbox', _providerCardLabel, 3000);
    if (!deleteBtn) {
      console.error('INFO: Delete Sandbox not visible — clicking Open Sandbox to reveal panel...');
      const openBtn = await _findScopedButton(page, 'Open Sandbox', _providerCardLabel, 5000);
      if (!openBtn) {
        const url = page.url();
        const btns = await page.evaluate(() =>
          Array.from(document.querySelectorAll('button'))
            .map(b => (b.innerText || b.textContent || '').trim())
            .filter(t => t.length > 0)
        ).catch(() => []);
        throw new Error(`Neither Delete Sandbox nor Open Sandbox visible. URL: ${url} | Buttons: ${JSON.stringify(btns)}`);
      }
      await openBtn.click({ force: true });
```

---

### Change 4 — `playwright/acg_restart.js`: scope `_startBtnPanel` and `deleteBtn` poll

**Exact old block (lines 297–324):**

```javascript
      // Poll for Delete Sandbox — dismiss Extend dialog on every tick so a late-appearing
      // dialog cannot block for more than one 500 ms interval.
      const _deletePollDeadline = Date.now() + 15000;
      let _deleteBtnReady = false;
      let _sandboxNotYetStarted = false;
      const _startBtnPanel = page.locator('button:has-text("Start Sandbox")').first();
      while (Date.now() < _deletePollDeadline) {
        await _dismissExtendYourSessionDialog(page);
        _deleteBtnReady = await deleteBtn.isVisible({ timeout: 500 }).catch(() => false);
        if (_deleteBtnReady) break;
        // Panel is open but sandbox not yet provisioned — Start Sandbox visible, Delete not.
        // Skip delete flow and start directly.
        if (await _startBtnPanel.isVisible({ timeout: 500 }).catch(() => false)) {
          _sandboxNotYetStarted = true;
          break;
        }
        await page.waitForTimeout(500).catch(() => {});
      }
      if (_sandboxNotYetStarted) {
        console.error('INFO: Sandbox panel open but not yet provisioned — clicking Start Sandbox directly...');
        await _startBtnPanel.scrollIntoViewIfNeeded().catch(() => {});
        await _startBtnPanel.click({ force: true });
        await page.waitForTimeout(3000);
        await _dismissExtendYourSessionDialog(page);
        console.error('INFO: Sandbox started. Ready for credential extraction.');
        console.log('RESTART_OK');
        return;
      }
```

**Exact new block:**

```javascript
      // Poll for Delete Sandbox — dismiss Extend dialog on every tick so a late-appearing
      // dialog cannot block for more than one 500 ms interval.
      const _deletePollDeadline = Date.now() + 15000;
      let _deleteBtnReady = false;
      let _sandboxNotYetStarted = false;
      let _startBtnPanelScoped = null;
      while (Date.now() < _deletePollDeadline) {
        await _dismissExtendYourSessionDialog(page);
        deleteBtn = await _findScopedButton(page, 'Delete Sandbox', _providerCardLabel, 0);
        _deleteBtnReady = deleteBtn !== null;
        if (_deleteBtnReady) break;
        // Panel is open but sandbox not yet provisioned — Start Sandbox visible, Delete not.
        // Skip delete flow and start directly.
        _startBtnPanelScoped = await _findScopedButton(page, 'Start Sandbox', _providerCardLabel, 0);
        if (_startBtnPanelScoped) {
          _sandboxNotYetStarted = true;
          break;
        }
        await page.waitForTimeout(500).catch(() => {});
      }
      if (_sandboxNotYetStarted) {
        console.error('INFO: Sandbox panel open but not yet provisioned — clicking Start Sandbox directly...');
        await _startBtnPanelScoped.scrollIntoViewIfNeeded().catch(() => {});
        await _startBtnPanelScoped.click({ force: true });
        await page.waitForTimeout(3000);
        await _dismissExtendYourSessionDialog(page);
        console.error('INFO: Sandbox started. Ready for credential extraction.');
        console.log('RESTART_OK');
        return;
      }
```

**Note on `timeoutMs = 0`:** `_findScopedButton` with `timeoutMs = 0` sets `deadline =
Date.now()`. The while condition `Date.now() <= deadline` is true on the first iteration
(both evaluated in the same synchronous tick), does a single DOM pass, then exits without
sleeping. Appropriate inside an outer 500ms-sleep poll loop.

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Add provider exclusion check to `startButton2` fallback loop |
| `playwright/acg_restart.js` | Add exclusion check to `_findScopedButton`; scope `deleteBtn`, `openBtn`, `_startBtnPanel` to target provider |
| `CHANGELOG.md` | Add `[Unreleased]` entry under `### Fixed` |
| `memory-bank/activeContext.md` | Update current status |
| `memory-bank/progress.md` | Update v0.1.4 track |

---

## Rules

- `node --check playwright/lib/sandbox.js` — zero errors
- `node --check playwright/acg_restart.js` — zero errors
- No other files touched

---

## Definition of Done

- [ ] `sandbox.js` fallback log message changed to `"trying provider-scoped fallback..."`
- [ ] `sandbox.js` fallback loop: `_fbOthers` computed; ancestor walk checks `(providerLabel matches) && !(any other provider matches)`; `if (inTargetCard) { startButton2 = btn; break; }`
- [ ] `acg_restart.js` `_findScopedButton` has `others` exclusion check — identical logic to `sandbox.js`'s version
- [ ] `acg_restart.js`: `const deleteBtn = page.locator(...)` → `let deleteBtn = await _findScopedButton(page, 'Delete Sandbox', _providerCardLabel, 3000)`
- [ ] `acg_restart.js`: `const openBtn = page.locator(...)` → `const openBtn = await _findScopedButton(page, 'Open Sandbox', _providerCardLabel, 5000)`
- [ ] `acg_restart.js`: `const _startBtnPanel = page.locator(...)` removed; replaced with `let _startBtnPanelScoped = null`
- [ ] `acg_restart.js`: poll loop uses `_findScopedButton(..., 0)` for both Delete and Start checks; `_sandboxNotYetStarted` path uses `_startBtnPanelScoped`
- [ ] `node --check playwright/lib/sandbox.js` passes
- [ ] `node --check playwright/acg_restart.js` passes
- [ ] `make check lint test` passes (run in lib-acg repo root)
- [ ] `CHANGELOG.md` updated under `### Fixed`
- [ ] Committed and pushed to `feat/v0.1.4`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(sandbox,acg_restart): scope startButton2 fallback and acg_restart button lookups to target provider
```

---

## What NOT to Do

- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/lib/sandbox.js` and `playwright/acg_restart.js` (plus `CHANGELOG.md` and `memory-bank/`)
- Do NOT commit to `main` — work on `feat/v0.1.4`
- Do NOT change `_findScopedButton` in `sandbox.js` — only the fallback loop changes in that file
- Do NOT change the fast-path `_deleteBtnCheck`/`_openBtnCheck` unscoped checks at lines 264–265 of `acg_restart.js` — those are intentionally unscoped (checking if ANY Delete/Open is present on the page)
- Do NOT touch `acg_credentials.js` or any provider file
