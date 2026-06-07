# Copilot PR #35 Review Findings

**PR:** #35 — refactor(acg-credentials): extract provider pattern
**Fix commit:** `04b2ca2`
**Date:** 2026-06-05

---

## Findings and Fixes

### 1. `sandbox.js:52` — `window.location.assign` without navigation wait

**Finding:** `page.evaluate(() => window.location.assign(...))` fired but subsequent steps ran against the previous document.

**Fix:** Added `await page.waitForLoadState('domcontentloaded', { timeout: 60000 }).catch(() => {})` after the evaluate call.

---

### 2. `sandbox.js:158` — `_dismissExtendYourSessionDialog` pressed Enter blindly

**Finding:** `bringToFront` + `keyboard.press('Enter')` can activate Cancel or do nothing; does not guarantee clicking "Extend Session."

**Fix:** Now finds `button:has-text("Extend")` within the dialog (alertdialog/dialog/testid variants) and clicks it specifically; falls back to `Enter` only when the button isn't found.

---

### 3. `sandbox.js:188` — Missing locator handler for "sandbox extended" toast

**Finding:** "Your sandbox has been extended." toast can intercept pointer events on the Open Sandbox button, causing flaky clicks.

**Fix:** Added `page.addLocatorHandler` for the toast text before the Start/Open button detection block.

---

### 4. `sandbox.js:225` — `openButton.click()` without `force: true`

**Finding:** Known susceptibility to pointer interception from transient overlays.

**Fix:** Changed to `openButton.click({ force: true })`.

---

### 5. `gcp.js:18` — Credential values logged in diagnostic output

**Finding:** `val.slice(0, 40)` in the input enumeration loop could expose the GCP password prefix or service account JSON prefix to logs.

**Fix:** Changed to `val.length > 0 ? '[set]' : '[empty]'` — key names visible, values never logged.

---

### 6. `gcp.js:47` — `writeFileSync mode:0o600` unreliable on overwrite

**Finding:** Node ignores the `mode` option when the file already exists on overwrite.

**Fix:** Added `fs.chmodSync(keyPath, 0o600)` immediately after `writeFileSync`.

---

### 7. `tests/providers/output.test.js:29` — Key-ordering-dependent assertion

**Finding:** `expect(spy).toHaveBeenCalledWith('FOO=bar\nBAZ=qux\n')` depends on `Object.entries()` ordering, which is not guaranteed.

**Fix:** Replaced with `arrayContaining` check on split lines + `toHaveLength(2)`.

---

### 8. `package.json:9` — `npm test` no longer runs Playwright e2e

**Finding:** Changing `"test"` from Playwright to Jest removes the default `npm test` e2e signal (though CI calls `npx playwright test` directly and is unaffected).

**Fix:** Added `"test:e2e": "npx playwright test"` so e2e remains accessible via `npm run test:e2e`.

---

## Process Note

When moving code verbatim per a refactor spec, Copilot will still flag pre-existing issues that were obscured in the monolith. For large refactors, run a Copilot review pass on the output even if behavior is unchanged — the new module boundaries make existing issues more visible.
