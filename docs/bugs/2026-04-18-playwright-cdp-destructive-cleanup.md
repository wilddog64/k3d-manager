# Bug: Playwright CDP destructive cleanup kills user browser

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/playwright/acg_credentials.js`

---

## Summary

When running `make up` with Chrome already open, the credential extraction script attempts to terminate the entire Google Chrome application upon completion or error. If no Pluralsight tab is already open, the script also hangs for 300s, during which the user's browser may become unresponsive.

---

## Reproduction Steps

1. Start Google Chrome with `--remote-debugging-port=9222`.
2. Ensure you have several tabs open (e.g., mail, chat), but **no Pluralsight tabs**.
3. Run `make up CLUSTER_PROVIDER=k3s-gcp`.
4. Observe the log: `INFO: CDP connected — no Pluralsight tab open, will open one in existing Chrome.`
5. Observe the hang: The script sits for 300s.
6. Observe the crash: After the timeout, the entire Google Chrome application is force-closed.

---

## Root Cause

1.  **Destructive API Usage:** The script incorrectly uses `browser.close()` in the `finally` block for CDP-connected sessions. 
    ```javascript
    // scripts/playwright/acg_credentials.js:443
    } finally {
      if (_cdpBrowser) {
        try { await _cdpBrowser.close(); } catch {} // THIS KILLS CHROME
      }
    }
    ```
    For CDP sessions, `.close()` attempts to terminate the remote application. The correct method to release the session without killing the process is **`.disconnect()`**.

2.  **Tab Deadlock:** When no Pluralsight tab is found, the script defaults to `pages()[0]` (the user's first tab). If this tab is a background/discarded tab, Playwright's `isVisible` or `locator` checks can hang indefinitely, leading to the 300s timeout. The script fails to explicitly call `await context.newPage()`.

---

## Proposed Fix

1.  **Switch to `disconnect()`**: Replace all instances of `_cdpBrowser.close()` with `_cdpBrowser.disconnect()`.
2.  **Explicit Page Creation**: If the target tab is not found in a CDP session, explicitly open a new tab using `await browserContext.newPage()` instead of reusing index 0.
3.  **Validation Guard**: Add a check to verify the page is interactive before running visibility probes on reused tabs.

---

## Impact

This is a **High Severity** stability bug. It results in data loss for the user (by killing their browser) and blocks all GCP/AWS extraction flows unless the environment is in a "perfect" state (Pluralsight tab already focused).
