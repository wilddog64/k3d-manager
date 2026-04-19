# Bug: Playwright CDP browser hijack and hang on cleanup

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/playwright/acg_credentials.js`, `scripts/playwright/gcp_iam_grant.js`

---

## Summary

Credential extraction hangs for 300s when Chrome is running via CDP. The log message `INFO: CDP connected — no Pluralsight tab open, will open one in existing Chrome.` is followed by a timeout. During this time, the user's primary browser may be hijacked or attempt to shut down entirely.

---

## Root Cause

1.  **Incorrect CDP Cleanup:** The script uses `browser.close()` on CDP connections. Unlike a launched browser, a CDP-connected `browser` object represents the user's actual running application. Calling `.close()` attempts to terminate the entire Chrome process, which often hangs on macOS and kills the user's active session.
2.  **Destructive Fallback:** When the CDP connection is lost or killed by a previous run, the script falls back to `launchPersistentContext`. This opens a **new browser window** with an isolated profile that lacks session cookies, leading to the `/id` login redirect and timeout.
3.  **Tab Hijacking:** If no target tab is found during a CDP session, the script tries to use `pages()[0]`, which hijacks the user's first open tab instead of opening a new one.

---

## Proposed Fix

1.  **Use `disconnect()` for CDP:** Replace `await browser.close()` with `browser.disconnect()` for all CDP-based sessions.
2.  **Explicit Tab Creation:** If the target tab (Pluralsight or GCP) is not found in the CDP session, explicitly call `await context.newPage()` to open a new tab in the user's existing window.
3.  **Global Timeouts:** Wrap all extraction logic in a `Promise.race` with a 300s limit to ensure the shell process always returns.

---

## Impact

This blocks all `make up` and `make refresh` operations when the user's browser is not in a specific state. It creates a destructive user experience by killing the primary browser application and spawning unauthenticated windows.
