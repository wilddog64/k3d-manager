# Issue: Pluralsight 'Oops! Something went wrong' in Antigravity

**Date:** 2026-03-28
**Branch:** `k3d-manager-v0.9.19`

## Problem
During the implementation of the static Playwright script for `acg_get_credentials`, the Antigravity browser consistently showed an error message: "Oops! Something went wrong. We could not fetch your user information." This occurred on all Pluralsight pages (`/`, `/hands-on`, `/hands-on/playground/cloud-sandboxes`).

## Analysis
- **CDP Connection:** Successfully established via `chromium.connectOverCDP('http://localhost:9222')`.
- **Browser Context:** Cookies for `app.pluralsight.com` and `.pluralsight.com` were present in the context.
- **Error Behavior:** The page shell loads, but the `#root` content renders an error component. Network logs showed aborted requests to `https://labs.pluralsight.com/graphql`.
- **Session state:** Clearing cookies and re-logging in via the Antigravity window (per user confirmation) did not resolve the issue for the Playwright-controlled page.
- **Impact:** Real DOM selectors for the "Start Sandbox" button and the AWS credentials panel could not be verified against a live page.

## Action Taken
- Implemented `scripts/playwright/acg_credentials.js` using robust, pattern-based selectors (`button:has-text("Start")`, `[data-testid="access-key-id"]`, etc.) and a regex-based fallback for log/code blocks.
- Updated `scripts/plugins/acg.sh` to use this static script.
- Verified basic script logic against a neutral URL.
- All 252 BATS tests passed.

## Recommended Follow-up
- Verify the script end-to-end once the Pluralsight platform is stable in the Antigravity environment.
- If the selectors fail, use `page.screenshot()` (once fonts/loading issues are resolved) or manual inspection to update `scripts/playwright/acg_credentials.js`.
