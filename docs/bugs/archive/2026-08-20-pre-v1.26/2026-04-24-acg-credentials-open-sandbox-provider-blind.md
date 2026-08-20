# Bug: `acg_credentials.js` — "Open Sandbox" click is provider-blind (deferred to lib-acg)

**Date:** 2026-04-24
**Status:** DEFERRED — will be fixed during lib-acg extraction
**Severity:** HIGH (GCP run clicks AWS "Open Sandbox" card)
**Branch:** `k3d-manager-v1.1.0`

## Summary

`acg_credentials.js` defines `openButton` as:
```js
const openButton = page.locator('button:has-text("Open Sandbox")').first();
```

The Cloud Sandboxes listing page has one "Open Sandbox" button per provider card:
- AWS Sandbox → "Open Sandbox"
- Azure Sandbox → "Open Sandbox"
- Google Cloud Sandbox → "Open Sandbox"

`.first()` always selects AWS. When `PROVIDER=gcp`, the script clicks the AWS card instead of
the Google Cloud card, which opens the wrong credential panel.

## Why Deferred

Fixing this in `scripts/playwright/acg_credentials.js` requires touching shared code that
serves both AWS and GCP flows. Any change risks destabilizing AWS (which is the pattern that
motivated the lib-acg extraction decision in the first place).

This bug will be corrected when `acg_credentials.js` is split into provider-isolated files
during the lib-acg extraction:
- `lib-acg/src/providers/aws/credentials.js` — hardcodes AWS card selector
- `lib-acg/src/providers/gcp/credentials.js` — hardcodes Google Cloud card selector

There is no cross-provider shared `openButton` in the new structure.

## Workaround

While deferred: GCP sandbox must be the ONLY active sandbox when running `acg-up` with
`CLUSTER_PROVIDER=k3s-gcp`. If both AWS and GCP sandboxes are running simultaneously,
the script will click the wrong card.

## Fix (for reference — do not apply to k3d-manager directly)

When implementing lib-acg `src/providers/gcp/credentials.js`:
```js
// Google Cloud card is always the target — no .first() needed when in a provider-isolated file
const openButton = page.locator(':has(button:has-text("Open Sandbox"))').filter({
  hasText: 'Google Cloud Sandbox'
}).locator('button:has-text("Open Sandbox")').first();
```

For `src/providers/aws/credentials.js`:
```js
const openButton = page.locator(':has(button:has-text("Open Sandbox"))').filter({
  hasText: 'AWS Sandbox'
}).locator('button:has-text("Open Sandbox")').first();
```

## Related

- `docs/plans/v1.1.0-acg-extraction-repo-split.md` — lib-acg extraction plan
- `docs/bugs/2026-04-24-acg-extend-ispanelopen-false-positive.md` — similar issue fixed in `acg_extend.js`
