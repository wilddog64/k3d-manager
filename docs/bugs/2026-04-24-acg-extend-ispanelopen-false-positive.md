# Bug: `acg_extend.js` — `isPanelOpen` false positive skips "Open Sandbox" click

**Date:** 2026-04-24
**Status:** OPEN
**Severity:** CRITICAL (Blocker — extend always fails on listing page)
**Branch:** `k3d-manager-v1.1.0`

## Summary

`acg_extend.js` fails to find the Extend button even when a sandbox is running and within the
1-hour extension window. The script correctly parses the TTL but then skips the "Open Sandbox"
click because `isPanelOpen` evaluates to `true` incorrectly — the "Auto Shutdown" text it checks
is visible on the **listing-page card**, not only inside an open sandbox panel.

## Terminal Output

```
INFO: Connected via CDP to existing browser session.
INFO: Already on Pluralsight page: https://app.pluralsight.com/hands-on/playground/cloud-sandboxes
INFO: Calculated remaining TTL: ~49 minutes
INFO: Within 1h extension window (49m remaining). Proceeding to extend...
ERROR: Extend button not found or not visible after multiple attempts (including recovery)
INFO: [acg] Extend failed — open https://app.pluralsight.com/hands-on/playground/cloud-sandboxes to extend manually
```

## Root Cause

**Problem A — `isPanelOpen` false positive (line 177):**
```js
const isPanelOpen = await page.locator('text=/Auto Shutdown/i').first().isVisible({ timeout: 2000 }).catch(() => false);
```
"Auto Shutdown at 11:59AM" is visible on the sandbox card on the **listing page**. This makes
`isPanelOpen = true`, so step 3 never clicks "Open Sandbox". The Extend button only appears
after clicking "Open Sandbox" to enter the sandbox detail view.

Step 1 already searched all `extendSelectors` and found nothing (`clicked = false`). If step 1
failed, the panel is definitively not open — `clicked` is the correct proxy for `isPanelOpen`.

**Problem B — provider-blind "Open Sandbox" (line 180):**
```js
const openButton = page.locator('button:has-text("Open Sandbox"), button:has-text("Open"), ...').first();
```
The listing page has one "Open Sandbox" button per provider card (AWS, Azure, Google Cloud).
`.first()` always picks AWS. When extending a GCP sandbox the wrong card is clicked.

The correct target: the card containing the "Auto Shutdown" banner (uniquely identifies the
running sandbox, regardless of provider).

## Files Implicated

- `scripts/playwright/acg_extend.js` (lines 175–186)

---

## Fix

One hunk — `scripts/playwright/acg_extend.js` only.

**Location:** lines 175–186 (the `// 3. Reveal the panel/modal` block).

**Old (lines 175–186):**
```js
    // 3. Reveal the panel/modal if still not clicked
    // Check if the details panel is already open
    const isPanelOpen = await page.locator('text=/Auto Shutdown/i').first().isVisible({ timeout: 2000 }).catch(() => false);
    
    if (!isPanelOpen) {
      const openButton = page.locator('button:has-text("Open Sandbox"), button:has-text("Open"), button:has-text("Start Sandbox"), button:has-text("Resume")').first();
      if (await openButton.isVisible({ timeout: 5000 }).catch(() => false)) {
        console.error('INFO: Clicking Open to reveal sandbox details...');
        await openButton.click({ force: true });
        await page.waitForTimeout(5000);
      }
    }
```

**New (lines 175–186):**
```js
    // 3. Reveal the panel/modal if still not clicked
    // isPanelOpen: "Auto Shutdown" text appears on the listing-page card — not a reliable signal
    // that the extend panel is open. If step 1 found no extend button, the panel is NOT open.
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
        await page.waitForTimeout(5000);
      }
    }
```

The `// 4. Second search for extend button` block that follows is unchanged.

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read `scripts/playwright/acg_extend.js` lines 110–200 in full (the full extend flow).
3. Read `memory-bank/activeContext.md`.
4. Run `node --check scripts/playwright/acg_extend.js` — must exit 0 before and after.
5. Do NOT touch `acg_credentials.js`.

---

## Rules

- `node --check scripts/playwright/acg_extend.js` must exit 0.
- Only `scripts/playwright/acg_extend.js` may be touched.
- Do NOT add `--no-verify` to any git command.
- Do NOT commit to `main`.
- Do NOT create a PR.

---

## Definition of Done

1. `scripts/playwright/acg_extend.js` lines 175–186 match the **New** block above exactly.
2. The `// 4. Second search for extend button` continuation at line 188 is unchanged.
3. `node --check scripts/playwright/acg_extend.js` exits 0.
4. Committed on `k3d-manager-v1.1.0` with message:
   ```
   fix(acg-extend): fix isPanelOpen false positive; click running sandbox Open button
   ```
5. Branch pushed to `origin/k3d-manager-v1.1.0` before reporting done.
6. `memory-bank/activeContext.md`: add entry for this fix as COMPLETE with real commit SHA.
7. `memory-bank/progress.md`: add `[x] **acg-extend isPanelOpen false positive** — COMPLETE (<sha>)` under Known Bugs / Gaps.
8. Report back: commit SHA + paste the memory-bank lines you updated.

---

## What NOT To Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside `scripts/playwright/acg_extend.js`.
- Do NOT commit to `main`.
- Do NOT touch `acg_credentials.js` or `acg_extend.js`'s Ghost State recovery block.
