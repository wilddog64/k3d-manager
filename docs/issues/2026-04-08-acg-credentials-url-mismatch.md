# Issue: acg_credentials URL mismatch triggers Cloudflare block

## Status
**Identified** (Fix Pending)

## Description
When running `make up` or `acg_get_credentials`, the automated extraction of AWS credentials fails. The logs show the script attempting to access the legacy URL, followed by an immediate error or timeout.

## Root Cause
1. **URL Redirect:** The script is hardcoded to navigate to `https://app.pluralsight.com/cloud-playground/cloud-sandboxes`. Pluralsight has migrated the sandbox UI to `https://app.pluralsight.com/hands-on/playground/cloud-sandboxes`.
2. **Cloudflare Protection:** The mismatch causes a server-side redirect. Cloudflare interprets this redirect from a Playwright-launched browser as bot behavior and triggers a challenge page, preventing the script from reaching the credential inputs.
3. **Session Fragmentation:** Launching a fresh browser process (even with a shared auth dir) instead of attaching to an existing verified session increases the likelihood of being challenged by Cloudflare.

## Impact
Users are unable to automatically provision or refresh their AWS credentials, blocking the `make up` cluster deployment process.

## Recommended Follow-up
1. Update `scripts/playwright/acg_credentials.js` to use the standardized `/hands-on/playground/` URL.
2. Ensure the script prioritizes **CDP connection** (port 9222) to reuse the user's active, human-verified browser session.
3. Apply the same URL standardization to `scripts/plugins/acg.sh` variables.
