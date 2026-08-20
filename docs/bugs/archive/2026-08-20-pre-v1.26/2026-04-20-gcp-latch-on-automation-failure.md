# Bug: GCP latch-on automation failed during functional E2E

**Branch:** `recovery-v1.1.0-aws-first`
**Files Implicated:** `scripts/playwright/gcp_login.js`

---

## Summary

During the final functional E2E test for Phase C, the manual extraction and identity switch worked, but the user was forced to manually click through the Google OAuth consent screens ("Managed Profile", "ToS", "Allow"). The Playwright script `gcp_login.js` failed to "latch on" to the new tab and automate these clicks as intended.

---

## Reproduction Steps

1. Run `CLUSTER_PROVIDER=k3s-gcp make up`.
2. Observe `gcloud auth login` triggering a new tab in Chrome.
3. Observe the browser waiting for user interaction on the "Choose an account" or "Managed Profile" screen.
4. Observe the terminal log showing `INFO: Detached from Chrome session` but no logs from the automation part of `gcp_login.js`.

---

## Root Cause (Suspected)

1. **Race Condition:** The `context.pages()` audit in `gcp_login.js` likely ran before macOS finished spawning the new tab, resulting in an empty search result.
2. **Search Scope:** The script may be looking in the wrong browser context if Chrome has multiple windows open with different profiles.
3. **Selector Timing:** The Google "Choose an account" screen may render faster than the script's polling loop, or use different DOM selectors than anticipated in the initial spec.

---

## Proposed Fix

1. **Patient Latching:** Upgrade the tab-search loop in `gcp_login.js` to poll for up to 30s with improved logging of every URL it sees.
2. **Browser-Level Wait:** Use `browser.on('targetcreated')` or `context.waitForEvent('page')` to catch the new tab the instant it is created by `gcloud`.
3. **Selector Hardening:** Verify the "Choose an account" and "Managed Profile" selectors against the latest Google UI.

---

## Impact

High. While the provider is functionally "working," it is not "automated." The user experience is degraded by requiring manual intervention during what should be a hands-off deployment.
