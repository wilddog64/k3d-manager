# Bugfix: Ghost State "Delete Sandbox" button not found after SPA navigation

**Branch:** `fix/acg-extend-ghost-state-spa-wait`
**Files:** `playwright/acg_extend.js`

---

## Problem

Ghost State Recovery fires (TTL < 15 min / expired), re-navigates to the listing URL, then
immediately checks `deleteBtn.isVisible({ timeout: 5000 })` — which times out because the
Pluralsight SPA has not finished rendering the sandbox card within 5 seconds of
`domcontentloaded`.

**Root cause:** `page.goto(..., { waitUntil: 'domcontentloaded' })` fires as soon as the
HTML shell loads. The React SPA then asynchronously renders the sandbox cards. The 5-second
`isVisible` timeout is too short for the card (and its "Delete Sandbox" button) to appear.

The button IS present on the page (confirmed by screenshot) but Playwright cannot see it
yet when the check runs.

---

## Reproduction

```
node acg_extend.js <sandbox-url>
# sandbox expired (TTL: -253m)
# expected:
#   INFO: Clicking Delete Sandbox...
# actual:
#   INFO: Saved extend failure screenshot to ...
#   ERROR: Extend button not found or not visible after multiple attempts (including recovery)
# (no "Clicking Delete Sandbox" line despite button being visible in browser)
```

---

## Fix

### Change 1 — `playwright/acg_extend.js`: add skeleton-loader wait + increase deleteBtn timeout

**Exact old block (lines 290–296):**

```javascript
      // Re-navigate to listing page — Open Sandbox or other interactions may have navigated away.
      await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 30000 }).catch(
        (e) => console.error(`WARN: Ghost State re-navigation failed: ${e.message}`)
      );

      const deleteBtn = page.locator('button:has-text("Delete Sandbox")').first();
      if (await deleteBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
```

**Exact new block:**

```javascript
      // Re-navigate to listing page — Open Sandbox or other interactions may have navigated away.
      await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 30000 }).catch(
        (e) => console.error(`WARN: Ghost State re-navigation failed: ${e.message}`)
      );

      // Wait for SPA to render sandbox cards after navigation (domcontentloaded fires before React renders)
      await page.waitForFunction(
        () => !document.querySelector('[aria-busy="true"]'),
        { timeout: 30000 }
      ).catch(() => console.error('WARN: Skeleton loaders did not clear after Ghost State re-navigation — proceeding'));

      const deleteBtn = page.locator('button:has-text("Delete Sandbox")').first();
      if (await deleteBtn.isVisible({ timeout: 30000 }).catch(() => false)) {
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_extend.js` | Add skeleton-loader wait after Ghost State re-navigation; increase deleteBtn isVisible timeout from 5s to 30s |

---

## Rules

- `node --check playwright/acg_extend.js` — zero errors
- No other files touched

---

## Definition of Done

- [ ] `node --check playwright/acg_extend.js` passes
- [ ] Committed to `fix/acg-extend-ghost-state-spa-wait` (new branch from lib-acg main)
- [ ] Pushed to `origin/fix/acg-extend-ghost-state-spa-wait`
- [ ] CHANGELOG `[Unreleased]` updated with one-line entry under `### Fixed`
- [ ] memory-bank/activeContext.md and memory-bank/progress.md updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-extend): wait for SPA render after Ghost State re-navigation; increase deleteBtn timeout to 30s
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_extend.js` and `CHANGELOG.md`
- Do NOT commit to `main` — work on `fix/acg-extend-ghost-state-spa-wait`
