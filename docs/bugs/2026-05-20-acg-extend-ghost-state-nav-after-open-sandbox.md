# Bugfix: Ghost State Recovery fails after "Open Sandbox" navigates away from listing page

**Branch:** `docs/next-improvements` (then subtree pull into k3d-manager)
**Files:** `playwright/acg_extend.js`

---

## Problem

When a sandbox is expired (TTL ≤ 0), Ghost State Recovery fires but "Delete Sandbox" is
never found, so the recovery fails with no actual deletion.

**Root cause (two issues):**

1. **"Open Sandbox" navigates away from listing page.** Step 3 (`!isPanelOpen`) clicks
   "Open Sandbox" for ALL cases where the extend button was not found immediately — including
   expired sandboxes. Clicking "Open Sandbox" opens a detail panel or navigates Playwright
   to a different page state where "Delete Sandbox" is no longer visible. Ghost State then
   runs on this new page state and `deleteBtn.isVisible()` returns false.

2. **Ghost State does not re-navigate to listing.** After Open Sandbox changes the page,
   Ghost State tries `page.locator('button:has-text("Delete Sandbox")')` without first
   returning to the listing URL where the button lives.

---

## Reproduction

```
sandbox Auto Shutdown: 2:02PM (expired ~4 hours ago)
node acg_extend.js <sandbox-url>
# expected:
#   INFO: Clicking Delete Sandbox...
#   INFO: Deletion confirmed. Waiting for Start button...
# actual (no "Clicking Delete Sandbox" line):
#   INFO: Clicking Open Sandbox to reveal extend panel...
#   INFO: Extend button missing in critical window. Attempting "Ghost State" recovery...
#   INFO: Saved extend failure screenshot to ...
#   ERROR: Extend button not found or not visible after multiple attempts (including recovery)
```

---

## Fix

### Change 1 — `playwright/acg_extend.js`: skip "Open Sandbox" when expired; re-navigate in Ghost State

**Exact old block (lines 229–295):**

```javascript
    const isPanelOpen = clicked;

    if (!isPanelOpen) {
      // Click "Open Sandbox" on the card with the "Auto Shutdown" banner (the running sandbox),
      // not .first() which always picks the first card (AWS) regardless of provider.
      const _allOpenBtns = page.locator('button:has-text("Open Sandbox")');
      const _btnCount = await _allOpenBtns.count();
      let _openBtn = null;
      for (let _i = 0; _i < _btnCount; _i++) {
        const _hasShutdown = await _allOpenBtns.nth(_i).evaluate(el => {
          let node = el.parentElement;
          for (let _j = 0; _j < 6; _j++) {
            if (!node) break;
            if (/auto\s*shutdown/i.test(node.innerText || '')) return true;
            node = node.parentElement;
          }
          return false;
        }).catch(() => false);
        if (_hasShutdown) { _openBtn = _allOpenBtns.nth(_i); break; }
      }
      if (!_openBtn) {
        _openBtn = page.locator('button:has-text("Open Sandbox"), button:has-text("Start Sandbox"), button:has-text("Resume")').first();
      }
      if (await _openBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
        console.error('INFO: Clicking Open Sandbox to reveal extend panel...');
        await _openBtn.click({ force: true });
        const _openPanelBtn = await _waitForVisibleExtendButton(page, extendSelectors, 15000, 'after Open Sandbox');
        if (_openPanelBtn) {
          await _openPanelBtn.click({ force: true });
          clicked = true;
        }
      }
    }

    // 5. "Ghost State" Recovery: If still not clicked and TTL is confirmed critical, Delete and Restart
    // Only trigger when remainingMins is definitively known to be critical — never on null (TTL parse
    // failure alone is not a strong enough signal to perform a destructive delete/restart action)
    if (!clicked && remainingMins !== null && remainingMins < 15) {
      console.error('INFO: Extend button missing in critical window. Attempting "Ghost State" recovery (Delete/Restart)...');
      
      const deleteBtn = page.locator('button:has-text("Delete Sandbox")').first();
```

**Exact new block:**

```javascript
    const isPanelOpen = clicked;

    // Skip "Open Sandbox" when sandbox is already expired — clicking it navigates Playwright
    // away from the listing page where "Delete Sandbox" lives, causing Ghost State to fail.
    const _isSandboxExpired = remainingMins !== null && remainingMins <= 0;
    if (!isPanelOpen && !_isSandboxExpired) {
      // Click "Open Sandbox" on the card with the "Auto Shutdown" banner (the running sandbox),
      // not .first() which always picks the first card (AWS) regardless of provider.
      const _allOpenBtns = page.locator('button:has-text("Open Sandbox")');
      const _btnCount = await _allOpenBtns.count();
      let _openBtn = null;
      for (let _i = 0; _i < _btnCount; _i++) {
        const _hasShutdown = await _allOpenBtns.nth(_i).evaluate(el => {
          let node = el.parentElement;
          for (let _j = 0; _j < 6; _j++) {
            if (!node) break;
            if (/auto\s*shutdown/i.test(node.innerText || '')) return true;
            node = node.parentElement;
          }
          return false;
        }).catch(() => false);
        if (_hasShutdown) { _openBtn = _allOpenBtns.nth(_i); break; }
      }
      if (!_openBtn) {
        _openBtn = page.locator('button:has-text("Open Sandbox"), button:has-text("Start Sandbox"), button:has-text("Resume")').first();
      }
      if (await _openBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
        console.error('INFO: Clicking Open Sandbox to reveal extend panel...');
        await _openBtn.click({ force: true });
        const _openPanelBtn = await _waitForVisibleExtendButton(page, extendSelectors, 15000, 'after Open Sandbox');
        if (_openPanelBtn) {
          await _openPanelBtn.click({ force: true });
          clicked = true;
        }
      }
    }

    // 5. "Ghost State" Recovery: If still not clicked and TTL is confirmed critical, Delete and Restart
    // Only trigger when remainingMins is definitively known to be critical — never on null (TTL parse
    // failure alone is not a strong enough signal to perform a destructive delete/restart action)
    if (!clicked && remainingMins !== null && remainingMins < 15) {
      console.error('INFO: Extend button missing in critical window. Attempting "Ghost State" recovery (Delete/Restart)...');

      // Re-navigate to listing page — Open Sandbox or other interactions may have navigated away.
      await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 30000 }).catch(
        (e) => console.error(`WARN: Ghost State re-navigation failed: ${e.message}`)
      );

      const deleteBtn = page.locator('button:has-text("Delete Sandbox")').first();
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_extend.js` | Skip Open Sandbox when expired; navigate to listing before Ghost State Delete |

---

## Rules

- `node --check playwright/acg_extend.js` — zero errors
- Code change limited to `playwright/acg_extend.js`; CHANGELOG and memory-bank updates are required documentation

---

## Definition of Done

- [ ] `node --check playwright/acg_extend.js` passes
- [ ] Committed to `docs/next-improvements` and pushed
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(acg-extend): skip Open Sandbox when expired; re-navigate to listing before Ghost State delete
```

---

## What NOT to Do

- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_extend.js`
- Do NOT commit to `main`
