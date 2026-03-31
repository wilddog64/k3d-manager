# Issue: `acg_get_credentials` Playwright extraction always falls back to stdin paste

**Date:** 2026-03-30
**Commit:** `52cf05e`
**File:** `scripts/playwright/acg_credentials.js`

---

## Symptoms

- `acg_get_credentials` always prints:
  ```
  INFO: [acg] Playwright extraction failed — falling back to stdin paste
  INFO: [acg] Copy the credentials block from the Pluralsight sandbox page, then run:
  INFO: [acg]   pbpaste | ./scripts/k3d-manager acg_import_credentials
  ```
- Chrome CDP was reachable (`curl http://localhost:9222/json` returned `"Cloud Playground Experience"`)
- User was already signed in manually — session was valid
- Script hung for ~60 seconds before failing
- Gemini e2e smoke test blocked on every run

---

## Root Causes

### Bug 1 — `isVisible()` with no timeout (silent false on page render race)

**Location:** lines 79, 83, 90, 95 (before fix)

```javascript
// Before — checks button visibility instantaneously
if (await startButton.isVisible()) {
} else if (await openButton.isVisible()) {
    const startButton2 = ...
    if (await startButton2.isVisible()) {
} else if (await resumeButton.isVisible()) {
```

Playwright's `locator.isVisible()` without a timeout argument returns the **current DOM state immediately** — it does not wait. After `waitForFunction` clears the `aria-busy` skeleton loader, the SPA continues rendering. The Start/Open/Resume buttons were not yet in the DOM at the instant `isVisible()` was called, so all three checks returned `false` silently.

The script then fell through to:
```javascript
await page.waitForSelector('input[aria-label="Copyable input"]', { timeout: 60000 });
```
…which timed out after 60 seconds because the sandbox panel was never opened.

**Fix:** Added `{ timeout: 5000 }` and `.catch(() => false)` to all three button checks:
```javascript
if (await startButton.isVisible({ timeout: 5000 }).catch(() => false)) {
} else if (await openButton.isVisible({ timeout: 5000 }).catch(() => false)) {
    if (await startButton2.isVisible({ timeout: 5000 }).catch(() => false)) {
} else if (await resumeButton.isVisible({ timeout: 5000 }).catch(() => false)) {
```

### Bug 2 — No sign-in detection (session expiry causes 60s hang)

**Location:** between `waitForFunction` block and `// 3. Handle Sandbox Start/Open Flow`

When the ACG Pluralsight session expired, the script navigated to the sandbox URL but landed on a sign-in prompt instead. There was no detection of the unauthenticated state — the script proceeded directly to looking for sandbox buttons (which were absent) and then timed out at `waitForSelector`.

**Fix:** Inserted sign-in detection block that:
1. Checks for a Sign In link/button (`a[href*="id.pluralsight.com"]`, `a:has-text("Sign In")`, `button:has-text("Sign In")`) with a 3s timeout
2. If visible: clicks it, waits for `id.pluralsight.com` redirect
3. Fills email field (uses `PLURALSIGHT_EMAIL` env var if set, otherwise waits for Google Password Manager auto-fill)
4. Handles two-step form (Continue button → password field)
5. Submits and waits for redirect back to `app.pluralsight.com`
6. Re-waits for SPA skeleton loaders to clear
7. If not visible: skips entirely (no-op for valid sessions)

---

## Process Notes

- `isVisible()` in Playwright is a **synchronous DOM snapshot** — always use `{ timeout: N }` when waiting for elements that may still be rendering after a navigation or SPA route change
- Session expiry was not detectable from the bash wrapper — the Playwright script must handle auth state internally
- Set `PLURALSIGHT_EMAIL` env var to pre-fill the email field and assist Google Password Manager lookup
