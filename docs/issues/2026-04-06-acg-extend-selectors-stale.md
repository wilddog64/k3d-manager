---
date: 2026-04-06
component: antigravity.sh / acg_extend.js
symptom: acg_watch extend fails every cycle
status: fix-ready (spec: docs/plans/v1.0.4-bugfix-acg-extend-selectors.md)
agent: Gemini (needs live sandbox)
---

# Issue: acg_extend.js — Extend button selectors stale against current Pluralsight UI

## Symptom

Every `acg_watch` TTL extension attempt fails:

```
INFO: [acg] Extending sandbox TTL...
INFO: [antigravity] Extending ACG sandbox TTL at https://app.pluralsight.com/cloud-playground/cloud-sandboxes...
INFO: [antigravity] acg_extend failed: INFO: Navigating to https://...
ERROR: Extend button not found or not visible after multiple attempts
INFO: [acg] Extend failed — open https://app.pluralsight.com/cloud-playground/cloud-sandboxes to extend manually
```

User can manually extend in browser — the button exists. Automation fails.

## Root Cause

Pluralsight's cloud-sandboxes UI has been updated since the selectors in
`scripts/playwright/acg_extend.js` were written. None of the 12 selectors in the
`extendSelectors` array (lines 66–79) match any visible button on the current page.

This has happened before (v1.0.2 selector fix, v1.0.3 spec that was never shipped).
The selectors need to be re-diagnosed against the live page and updated.

## Files Involved

| File | Issue |
|------|-------|
| `scripts/playwright/acg_extend.js` | `extendSelectors` array (lines 66–79) stale |

## Fix

Gemini task — requires live sandbox. Run `debug_buttons.js` against
`https://app.pluralsight.com/cloud-playground/cloud-sandboxes`, capture all visible
buttons, identify the correct selector, update the `extendSelectors` array.

See `docs/plans/v1.0.4-bugfix-acg-extend-selectors.md`.
