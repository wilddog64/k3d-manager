# Bug: Playwright extraction fails on /hands-on landing page redirect

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/playwright/acg_credentials.js`

---

## Summary

`make up` fails with a timeout during credential extraction if the user's Pluralsight session is invalid. Instead of redirecting to `/id` (which the script handles), Pluralsight sometimes redirects to the course landing page (`/hands-on`). The script fails to recognize this as an unauthenticated state and hangs while waiting for sandbox-specific selectors.

---

## Reproduction Steps

1. Close all Pluralsight tabs in Chrome.
2. Clear Pluralsight cookies or allow the session to expire.
3. Run `make up CLUSTER_PROVIDER=k3s-gcp`.
4. Observe the log: `INFO: Navigating to https://app.pluralsight.com/hands-on/playground/cloud-sandboxes...`
5. Observe the redirect: The script navigates but lands on `https://app.pluralsight.com/hands-on`.
6. Observe the hang: The script waits 15-30s for `text=Username` or `button:has-text("Sandbox")` which are not present on the landing page.

---

## Root Cause

The script's unauthenticated state detection is too specific:

```javascript
// scripts/playwright/acg_credentials.js:250
if (page.url().includes('/id')) {
  console.error('INFO: Pluralsight redirected to /id — waiting for manual sign-in...');
  // ...
}
```

If Pluralsight redirects to `/hands-on` or `/home` instead of `/id`, the script skips the wait block and attempts to extract credentials from a course catalog page, leading to a `TimeoutError`.

---

## Proposed Fix

1.  **URL Validation:** After navigation, check if the current URL contains the string `cloud-sandboxes`. 
2.  **Generic Wait Loop:** If the URL is incorrect (either `/id`, `/hands-on`, or `/home`), trigger a 300s "Waiting for user" loop that polls the URL until it matches the requested sandbox dashboard path.

---

## Impact

This bug causes consistent flakiness when starting work in a fresh terminal session. It prevents the automation from gracefully handing control back to the user for login, resulting in confusing "Timeout" errors instead of "Action Required" messages.
