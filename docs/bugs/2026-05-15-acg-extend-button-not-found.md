# Bug: acg_extend — Extend button not found after "Open Sandbox" click

**Date:** 2026-05-15
**File:** `scripts/lib/acg/playwright/acg_extend.js`
**Symptom:** Script logs "Extend button not found or not visible after multiple attempts (including recovery)"
**Root cause:** Pluralsight redesigned the sandbox UI. The credential panel (shown after clicking "Open Sandbox") no longer contains an "Extend Session" button. The extend action is now triggered differently.

---

## Observed behavior (from log)

```
INFO: Already on sandbox page: https://app.pluralsight.com/hands-on/playground/cloud-sandboxes
INFO: Calculated remaining TTL: ~50 minutes
INFO: Within 1h extension window (50m remaining). Proceeding to extend...
INFO: Clicking Open Sandbox to reveal extend panel...
ERROR: Extend button not found or not visible after multiple attempts (including recovery)
```

The browser page after the failure shows:
- "Delete Sandbox" (outlined) and "Open Sandbox" (filled) buttons
- "Auto Shutdown at 10:53PM" section
- Credentials panel (username, password, access keys)
- No "Extend Session" button visible anywhere in this view

---

## Root cause

`acg_extend.js` clicks "Open Sandbox" to "reveal the extend panel". In the new Pluralsight UI, clicking "Open Sandbox" shows ONLY the credential panel — the extend button is no longer in that panel.

The extend button is now likely:
1. On the LISTING PAGE card (before clicking "Open Sandbox") — possibly labeled differently or using a different element
2. Triggered by clicking directly on the "Auto Shutdown at HH:MMpm" text/section
3. In a dropdown/menu not previously tried

---

## Fix

**File:** `scripts/lib/acg/playwright/acg_extend.js`

### Change 1 — Take a mid-process debug screenshot before clicking "Open Sandbox"

Add a screenshot step after the TTL check so we can see the listing page state:

**After line 237 (after the `WARN: Auto Shutdown text not found` else block), add:**

```javascript
    // Debug: capture listing page state before attempting reveal
    {
      const _debugDir = path.join(os.homedir(), '.local', 'share', 'k3d-manager');
      const _debugPath = path.join(_debugDir, `acg-extend-debug-listing-${Date.now()}.png`);
      try {
        await fs.promises.mkdir(_debugDir, { recursive: true });
        await page.screenshot({ path: _debugPath, fullPage: true });
        console.error(`INFO: Debug screenshot (listing page): ${_debugPath}`);
      } catch (_e) { /* non-fatal */ }
    }
```

### Change 2 — Try clicking "Auto Shutdown" section before falling back to "Open Sandbox"

The "Auto Shutdown at HH:MMpm" text may now be the trigger for the extend modal. Try it BEFORE clicking "Open Sandbox".

**Replace the `if (!isPanelOpen)` block (lines ~244–274) with:**

```javascript
    if (!isPanelOpen) {
      // NEW: Try clicking the "Auto Shutdown" section — may trigger extend modal in redesigned UI
      const _shutdownLink = page.locator('text=/Auto Shutdown/i').first();
      if (await _shutdownLink.isVisible({ timeout: 3000 }).catch(() => false)) {
        console.error('INFO: Clicking Auto Shutdown section to trigger extend modal...');
        await _shutdownLink.click({ force: true });
        await page.waitForTimeout(2000);
        const _shutdownPanelBtn = await _waitForVisibleExtendButton(page, extendSelectors, 10000, 'after AutoShutdown click');
        if (_shutdownPanelBtn) {
          await _shutdownPanelBtn.click({ force: true });
          clicked = true;
        }
      }

      // Fallback: click "Open Sandbox" on the card with the "Auto Shutdown" banner
      if (!clicked) {
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

          // After opening, scroll to top — extend button may be above the fold
          await page.evaluate(() => window.scrollTo(0, 0)).catch(() => {});
          await page.waitForTimeout(1000);

          const _openPanelBtn = await _waitForVisibleExtendButton(page, extendSelectors, 15000, 'after Open Sandbox');
          if (_openPanelBtn) {
            await _openPanelBtn.click({ force: true });
            clicked = true;
          }

          // NEW: If extend button still not found, take a screenshot of what we see
          if (!clicked) {
            const _debugDir = path.join(os.homedir(), '.local', 'share', 'k3d-manager');
            const _debugPath = path.join(_debugDir, `acg-extend-debug-after-open-${Date.now()}.png`);
            try {
              await fs.promises.mkdir(_debugDir, { recursive: true });
              await page.screenshot({ path: _debugPath, fullPage: true });
              console.error(`INFO: Debug screenshot (after Open Sandbox): ${_debugPath}`);
            } catch (_e) { /* non-fatal */ }
          }
        }
      }
    }
```

### Change 3 — Broaden the extendSelectors array

Add selectors for the redesigned Pluralsight UI that may use different attributes:

**Add to `extendSelectors` array (after the existing entries):**

```javascript
      // Redesigned UI selectors (2025+)
      'a:has-text("Extend")',
      '[class*="extend" i]',
      '[href*="extend" i]',
      'button[class*="Extend"]',
      'span:has-text("Extend Session")',
      'div[role="button"]:has-text("Extend")',
```

---

## Definition of Done

- [ ] `node --check scripts/lib/acg/playwright/acg_extend.js` passes
- [ ] On next `acg_extend` run: debug screenshots are saved to `~/.local/share/k3d-manager/`
- [ ] The debug screenshots reveal where the extend button actually is in the current Pluralsight UI
- [ ] Commit message: `fix(acg): add Auto Shutdown click, debug screenshots, and broader extend selectors`
- [ ] Push: `git push origin k3d-manager-v1.4.6`
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA

## What NOT to do

- Do NOT create a PR
- Do NOT skip pre-commit hooks
- Do NOT modify files outside `scripts/lib/acg/playwright/acg_extend.js`
- Do NOT commit to `main`
- Work on branch: `k3d-manager-v1.4.6`

## Before you start

- `git pull origin k3d-manager-v1.4.6`
- Read this spec in full
- Read `scripts/lib/acg/playwright/acg_extend.js` in full before editing
