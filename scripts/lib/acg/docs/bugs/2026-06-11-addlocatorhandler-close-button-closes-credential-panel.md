# Bug: addLocatorHandler close button closes credential panel — regression from a34cd3c

**Date:** 2026-06-11
**Repo:** lib-acg
**Branch:** feat/v0.1.5
**File:** `playwright/lib/sandbox.js`

---

## Symptom

`make credential-test PROVIDER=azure` fails with:

```
WARN: Azure panel stayed closed after reopen attempt — aborting instead of looping for 420s.
ERROR: Azure panel stayed closed after reopen attempt — aborting instead of looping for 420s.
ERROR: Credential extraction still failing after restart.
```

---

## Root Cause

In v0.1.4, the `addLocatorHandler` trigger `text=/sandbox has been extended|session extended/i`
caused a strict mode violation (matched both `<h3>` and `<p>`) — the `.catch(() => {})`
swallowed the error so the handler **never fired**. The session-extended toast appeared but
caused no harm.

`a34cd3c` fixed the trigger to `page.locator('h3, h2').filter({ hasText: /.../ }).first()`.
The handler now **fires correctly** when the toast appears. But the handler body uses an
unscoped close button:

```javascript
const closeBtn = page.locator(
  'button[aria-label="close"], button[aria-label="Close"], button[aria-label="Dismiss"]'
).first();
```

When the session-extended toast appears while the Azure credential panel is open, the
**credential panel's own close button** appears first in DOM order. The handler clicks it,
closing the credential panel. The toast is NOT dismissed. The handler fires again. The
credential panel keeps getting closed. `_waitForCredentials` gives up after one reopen
attempt and throws.

---

## Fix

Replace the unscoped close button click with `Escape`. `Escape` dismisses the
session-extended toast without targeting any DOM button, so it cannot accidentally close the
credential panel.

Keep the existing `inputsVisible` recovery check (in case Escape closes the panel on some
browsers) — it becomes the safety net, not the primary path.

### Change 1 — `playwright/lib/sandbox.js`: use Escape in addLocatorHandler

**Exact old block (lines 393–401):**

```javascript
    async () => {
      const closeBtn = page.locator(
        'button[aria-label="close"], button[aria-label="Close"], button[aria-label="Dismiss"]'
      ).first();
      if (await closeBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
        await closeBtn.click({ force: true }).catch(() => {});
      } else {
        await page.keyboard.press('Escape').catch(() => {});
      }
      await page.waitForTimeout(800);
```

**Exact new block:**

```javascript
    async () => {
      await page.keyboard.press('Escape').catch(() => {});
      await page.waitForTimeout(800);
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Replace unscoped close button click with `Escape` in `addLocatorHandler` handler |

---

## Rules

- `node --check playwright/lib/sandbox.js` must pass
- No other files touched

---

## Definition of Done

- [ ] Handler body replaced: `closeBtn` locator + if/else removed; `await page.keyboard.press('Escape').catch(() => {});` is the first line
- [ ] `await page.waitForTimeout(800);` remains
- [ ] `inputsVisible` recovery block (lines 402–412) unchanged
- [ ] `node --check playwright/lib/sandbox.js` passes
- [ ] Committed and pushed to `feat/v0.1.5`
- [ ] memory-bank updated with commit SHA and task status (in k3d-manager repo)

**Commit message (exact):**
```
fix(sandbox): use Escape in addLocatorHandler — unscoped close button was closing credential panel
```

---

## What NOT to Do

- Do NOT create a PR yourself — Claude handles PR creation after verifying the commit
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/lib/sandbox.js`
- Do NOT commit to `main` — work on `feat/v0.1.5`
- Do NOT remove the `inputsVisible` recovery block — keep it as a safety net
