# Bug: Playwright extraction falls back to clean context if Pluralsight tab is missing

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/playwright/acg_credentials.js`

---

## Summary

Running `make up` (or any credential extraction) fails with a timeout if the user does not already have a Pluralsight tab open in their Chrome browser. The script falls back to launching a new persistent context, which has no cookies, triggering a redirect to `/id` and waiting 300 seconds for a manual login that the user isn't aware they need to perform.

---

## Reproduction Steps

1. Start the Chrome CDP agent (`--remote-debugging-port=9222`).
2. Ensure you are logged into Pluralsight in Chrome, but **close any open Pluralsight tabs**.
3. Run `make up CLUSTER_PROVIDER=k3s-gcp` (or `k3s-aws`).
4. Observe the output: The script connects to CDP but does not log `Found existing Pluralsight session via CDP`.
5. It then launches a clean browser context, navigates to the target URL, gets redirected to `/id`, and hangs for 300 seconds.

---

## Root Cause

In `scripts/playwright/acg_credentials.js`, the CDP connection logic contains this flaw:

```javascript
const _cdpPsPage = _cdpPages.find(p => {
  try { return new URL(p.url()).hostname.endsWith('.pluralsight.com'); } catch { return false; }
});
if (_cdpPsPage) {
  console.error('INFO: Found existing Pluralsight session via CDP...');
  browserContext = _cdpContext;
}
```

Because `browserContext` is only set if a Pluralsight page is *already open*, closing the tab causes `browserContext` to remain undefined. The script then proceeds to fallback:

```javascript
if (!browserContext) {
  browserContext = await chromium.launchPersistentContext(AUTH_DIR, ...);
}
```

This launches a separate persistent context located in `~/.local/share/k3d-manager/playwright-auth/`. This isolated profile lacks the user's active session cookies, so Pluralsight forces a login (`/id`), resulting in a timeout.

---

## Proposed Fix

Update the CDP logic to reuse the `_cdpContext` regardless of whether a Pluralsight tab is currently open. If the connection succeeds, the script should just use that context and open a new tab (`await _cdpContext.newPage()`) to navigate to the sandbox URL. The persistent context fallback should only be triggered if the CDP connection itself fails (e.g., Chrome is not running).

---

## Impact

This introduces severe flakiness to the `make up` process. Users must remember to keep a Pluralsight tab actively open in their browser; otherwise, the automation fails silently in the background waiting for a login in an isolated profile window.
