# Bugfix: v0.1.4 — Delete Sandbox confirm dialog not clicked (React synthetic event miss)

**Branch:** `feat/v0.1.4`
**Files:** `playwright/lib/sandbox.js`, `CHANGELOG.md`, `memory-bank/activeContext.md`, `memory-bank/progress.md`

---

## Problem

`_deleteConflictingSandbox` clicks "Delete Sandbox" but the confirmation dialog that appears
is never confirmed. The AWS sandbox stays running. ACG then disables the Azure "Start Sandbox"
button (one active sandbox at a time), so the Azure flow stalls at:

```
INFO: Start Sandbox button is disabled — sandbox already running; waiting for credentials...
INFO: Waiting for Azure credentials to populate (up to 420s)...
```

**Root cause:** Lines 260–266 use `page.evaluate(() => btn.dispatchEvent(new MouseEvent(...)))`.
React apps ignore plain DOM `MouseEvent` dispatches — only Playwright's own `click()` fires
the synthetic event system. The confirmation button is never activated.

---

## Fix

### Change 1 — `playwright/lib/sandbox.js`: replace `dispatchEvent` with Playwright `click()`

**Exact old block (lines 259–266):**

```javascript
  await page.waitForTimeout(1500);
  await page.evaluate(() => {
    const dialog = document.querySelector('[role="alertdialog"]');
    if (!dialog) return;
    const btn = Array.from(dialog.querySelectorAll('button'))
      .find(b => /delete sandbox/i.test(b.textContent || ''));
    if (btn) btn.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
  }).catch(() => {});
```

**Exact new block:**

```javascript
  await page.waitForTimeout(1500);
  const confirmBtn = page.locator('[role="alertdialog"] button', { hasText: /delete sandbox/i });
  if (await confirmBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
    await confirmBtn.click({ force: true });
  }
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Replace `page.evaluate`+`dispatchEvent` with Playwright `confirmBtn.click()` |
| `CHANGELOG.md` | Add `[Unreleased]` entry under `### Fixed` |
| `memory-bank/activeContext.md` | Update current status |
| `memory-bank/progress.md` | Update v0.1.4 track |

---

## Rules

- `node --check playwright/lib/sandbox.js` — zero errors
- Do NOT touch any other file

---

## Definition of Done

- [ ] Lines 260–266 replaced with the two-line Playwright locator+click block
- [ ] `node --check playwright/lib/sandbox.js` passes
- [ ] `CHANGELOG.md` updated with entry under `### Fixed`
- [ ] Committed and pushed to `feat/v0.1.4`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(sandbox): replace dispatchEvent with Playwright click for delete confirm dialog — React ignores synthetic event miss
```

---

## What NOT to Do

- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/lib/sandbox.js` (plus `CHANGELOG.md` and `memory-bank/`)
- Do NOT commit to `main` — work on `feat/v0.1.4`
- Do NOT change `_findScopedButton`, `_waitForCredentials`, or `startSandbox`
- Do NOT touch `azure.js`, `acg_credentials.js`, or any provider file
