# Bug: acg_extend.js leaves "Session extended" modal open after CDP extend

**Date:** 2026-05-01
**Severity:** Low — sandbox IS extended; modal is cosmetic but blocks the browser UI
**Root cause:** `acg_extend.js` dismisses stale "Session extended" modals *before* clicking the extend button (line 138–154) but does not dismiss the *new* confirmation modal that appears *after* clicking. In CDP mode the browser stays running, so the modal persists after the script exits.

**Evidence:** After a successful `acg-extend` run via CDP, the ACG portal shows a "Session extended — Your sandbox has been extended." modal that must be manually closed.

---

## Before You Start

1. Read `memory-bank/activeContext.md` and `memory-bank/progress.md` in k3d-manager.
2. `git pull origin k3d-manager-v1.3.0` in k3d-manager to get this spec.
3. Read this spec in full before touching anything.
4. Read the target file before editing:
   - `scripts/lib/acg/playwright/acg_extend.js` (k3d-manager subtree copy)
   - `playwright/acg_extend.js` (lib-acg standalone)
5. Branch (k3d-manager): `k3d-manager-v1.3.0` — commit directly, no new branch.
6. Branch (lib-acg): `main` — commit directly.

---

## What to Change

Both copies of `acg_extend.js` need the same change.

**Location:** After the confirmation check block (line 331 — `if (!confirmed) { ... }`), before the expiry text read.

**Before** (lines 333–337 in k3d-manager copy):
```javascript
    if (!confirmed) {
      console.error('WARN: Could not confirm extension via toast/TTL text — proceeding anyway');
    }

    const expiryText = await page.locator('text=/expires/i').first().textContent().catch(() => 'unknown');
```

**After:**
```javascript
    if (!confirmed) {
      console.error('WARN: Could not confirm extension via toast/TTL text — proceeding anyway');
    }

    // Dismiss the post-extend "Session extended" confirmation modal so the browser UI is clean
    const _postExtendModal = page.locator('text="Session extended"').first();
    if (await _postExtendModal.isVisible({ timeout: 2000 }).catch(() => false)) {
      console.error('INFO: Dismissing post-extend "Session extended" modal...');
      await page.keyboard.press('Escape').catch(() => {});
      await page.waitForTimeout(300);
      const _postCloseBtn = page.locator('[role="dialog"] button, button:has-text("×"), button[aria-label*="close" i]').first();
      if (await _postExtendModal.isVisible({ timeout: 1000 }).catch(() => false) &&
          await _postCloseBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
        await _postCloseBtn.click({ force: true }).catch(() => {});
      }
    }

    const expiryText = await page.locator('text=/expires/i').first().textContent().catch(() => 'unknown');
```

---

## Definition of Done

- [ ] `scripts/lib/acg/playwright/acg_extend.js` — post-extend modal dismiss block inserted
- [ ] `playwright/acg_extend.js` in lib-acg — identical change applied
- [ ] No other files modified
- [ ] `node --check scripts/lib/acg/playwright/acg_extend.js` passes
- [ ] `node --check playwright/acg_extend.js` in lib-acg passes
- [ ] Commit on `k3d-manager-v1.3.0` with exact message:
  ```
  fix(acg-extend): dismiss post-extend "Session extended" modal in CDP mode

  Pre-extend dismissal (line 138) clears stale modals before searching for
  the extend button. Post-extend dismissal (new) clears the confirmation
  modal that appears after a successful click so the browser UI is clean
  when the script exits in CDP mode.
  ```
- [ ] Commit on lib-acg `main` with exact message:
  ```
  fix(acg-extend): dismiss post-extend "Session extended" modal in CDP mode

  Pre-extend dismissal (line 138) clears stale modals before searching for
  the extend button. Post-extend dismissal (new) clears the confirmation
  modal that appears after a successful click so the browser UI is clean
  when the script exits in CDP mode.
  ```
- [ ] `git push origin k3d-manager-v1.3.0` in k3d-manager succeeds
- [ ] `git push origin main` in lib-acg succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` in k3d-manager with both SHAs
- [ ] Report back: both SHAs + paste the memory-bank lines updated

---

## What NOT to Do

- Do NOT create PRs
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside `playwright/acg_extend.js` in each repo
- Do NOT commit to `main` in k3d-manager

---

## Rules

- Two repos, same one-file change — if your diff touches anything else, stop and re-read the spec
- `node --check` must pass on both files before committing
