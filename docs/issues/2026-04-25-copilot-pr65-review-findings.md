# Copilot PR #65 Review Findings

**PR:** #65 feat(v1.1.0): unified ACG automation AWS + GCP
**Date:** 2026-04-25

## Finding 1 — CodeQL: clear-text logging of sensitive information

**File:** `scripts/playwright/gcp_login.js:90`
**What Copilot flagged:** `console.error(\`INFO: Entering email ${GCP_ACCOUNT}...\`)` — CodeQL "Clear-text logging of sensitive information" because `GCP_ACCOUNT` is derived from `process.env`.

**Fix applied (`60a04418`):**
```js
// Before
console.error(`INFO: Entering email ${GCP_ACCOUNT}...`);

// After
console.error('INFO: Entering email...');
```

**Root cause:** Interpolating an env-derived value (email address) into a console log. CodeQL treats all `process.env` reads as potentially sensitive.

**Process note:** Add to spec template — log messages in `.js` files must not interpolate `process.env` values; use generic strings for credential-adjacent fields.
