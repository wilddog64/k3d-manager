# Bug: Playwright CDP browser hijack and hang on cleanup

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/playwright/acg_credentials.js`

---

## Summary

Credential extraction hangs for 300s when Chrome is running via CDP. The log message `INFO: CDP connected — no Pluralsight tab open, will open one in existing Chrome.` is followed by a timeout. During this time, the user's primary browser may be hijacked or attempt to shut down.

---

## Root Cause

The script incorrectly calls `_cdpBrowser.close()` in the `finally` block when connected via CDP:

```javascript
// scripts/playwright/acg_credentials.js line 443
} finally {
  if (_cdpBrowser) {
    try { await _cdpBrowser.close(); } catch {}
  }
}
```

In Playwright, when connected to a running browser via CDP, the `browser` object represents the entire application. Calling `.close()` on it attempts to terminate the user's Chrome process. On macOS, this often hangs if other windows are open, leading to the 300s timeout observed by the user.

Furthermore, if no Pluralsight tab is found, the script fails to explicitly open a new one within the CDP context, leading to a hang during navigation checks.

---

## Proposed Fix

1.  **Use `disconnect()` for CDP:** Replace `_cdpBrowser.close()` with `_cdpBrowser.disconnect()`.
2.  **Explicit Tab Creation:** If `_cdpPsPage` is not found, call `await _cdpContext.newPage()` before attempting any navigation or `isVisible` checks.

---

## Impact

This blocks all `make up` operations when a Pluralsight tab is not already the active/open tab in the user's browser, and it creates a destructive user experience by attempting to kill their browser process.
