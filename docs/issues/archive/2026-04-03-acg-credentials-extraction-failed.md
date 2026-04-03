# Issue: acg_get_credentials failed during E2E bootstrap

**Date:** 2026-04-03
**Branch:** `k3d-manager-v1.0.2`

## Problem
The `acg_get_credentials` function failed to extract AWS credentials from the Pluralsight sandbox page during the Gemini E2E verification task.

## Symptoms
- Command: `./scripts/k3d-manager acg_get_credentials "https://app.pluralsight.com/hands-on/playground/cloud-sandboxes"`
- Output: `INFO: [acg] Playwright extraction failed — falling back to stdin paste`
- Sandbox State: User confirmed they signed in and the sandbox was recreated. 4 empty boxes and 'Start Sandbox' button were expected.

## Analysis
- The script `scripts/playwright/acg_credentials.js` was expected to click 'Start Sandbox' and wait for credentials to populate.
- Despite profile locks being cleared, the script failed to find or extract the keys.
- Possible causes:
    1. UI changed on Pluralsight platform.
    2. The 60s timeout for credentials to populate was exceeded.
    3. The browser context failed to reuse the user's manual sign-in session.

## Impact
Blocks Part 2 of the E2E verification (vault-bridge e2e) as no AWS credentials are available to run `bin/acg-up`.

## Recommended Follow-up
- Inspect `scratch/` for any automated screenshots if they were generated (though not part of the standard script's failure path).
- Increase logging in `acg_credentials.js` to pinpoint the failure step (selector timeout vs logic mismatch).
