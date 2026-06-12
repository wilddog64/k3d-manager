# Copilot PR #44 review findings

**Date:** 2026-06-12
**PR:** #44 — fix: Azure SP validation restart + sandbox conflict detection (v0.1.7)
**Branch:** `feat/v0.1.7`

---

## Finding 1 — `isDisabled()` uses default 30s timeout in credential wait loop

**File:** `playwright/lib/sandbox.js:259`

**Copilot:** `btn.isDisabled()` uses Playwright's default timeout (~30s). In `_waitForCredentials`'s
Start-Sandbox scan loop it can stall for long periods when a Start Sandbox button is
detached/loading, reducing polling cadence and risking a premature 420s timeout. Use a short
timeout like the surrounding `isVisible({ timeout: 300 })`.

**Root cause:** `isDisabled()` was added without an explicit timeout while the adjacent
`isVisible()` call was already bounded to 300ms. A transient detached/loading button would
block the loop iteration for up to the default 30s.

**Fix (`87a7ff3`):**

```js
// before
const disabled = await btn.isDisabled().catch(() => false);
// after
const disabled = await btn.isDisabled({ timeout: 300 }).catch(() => false);
```

**Process note:** when adding a Playwright state probe (`isVisible` / `isDisabled` /
`isEnabled` / `isChecked`) inside a polling loop, always pass an explicit short `{ timeout }`
matching the loop cadence — the default 30s silently throttles the loop. Add to the Azure/
Playwright review checklist.
