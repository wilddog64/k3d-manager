# Bug: Playwright extraction fails with ProcessSingleton lock error

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/playwright/acg_credentials.js`, `scripts/playwright/gcp_iam_grant.js`

---

## Summary

`make up` (and other credential extraction flows) suddenly fails with:

```text
ERROR: browserType.launchPersistentContext: Failed to create a ProcessSingleton for your profile directory. 
This usually means that the profile is already in use by another instance of Chromium.
```

Reproduction confirms that a dangling `SingletonLock` file exists in `~/.local/share/k3d-manager/playwright-auth/`, preventing any new Playwright sessions from starting.

---

## Reproduction Steps

1. Run any Playwright-based script using `launchPersistentContext` (e.g., `acg_credentials.js`).
2. Cause the script to exit forcefully (e.g., via a `process.exit(1)` inside a guard clause) or allow it to hang in a loop.
3. Observe that the Chrome process may remain active or the `SingletonLock` symlink is not deleted from the auth directory.
4. Run `make up` again.
5. Extraction fails immediately with the `ProcessSingleton` error.

---

## Root Cause

1.  **Improper Cleanup:** Recent additions of "Identity Guards" used `process.exit(1)` to abort the script on account mismatch. This prevented the `finally` block or the `browser.close()` call from executing, leaving the profile locked.
2.  **Infinite Loops:** Experimental login logic included a `while (page.url().includes(...))` loop without a global timeout, leading to hung processes that kept the lock active.
3.  **Shared Profile:** Both AWS and GCP extraction paths use the same `playwright-auth` directory; a crash in one blocks the other.

---

## Proposed Fix

1.  **Mandatory `finally` Cleanup:** Refactor all Playwright scripts to ensure `browser.close()` or `browserContext.close()` is called in a `finally` block, and avoid using `process.exit()` inside the main logic.
2.  **Overall Timeouts:** Wrap the main execution in a `Promise.race` with a global timeout (e.g., 5-6 minutes) to ensure scripts never hang indefinitely.
3.  **CDP Latch-on Hardening:** Prioritize connecting to an existing Chrome instance via CDP (port 9222). If successful, no new `PersistentContext` (and thus no new lock) is required.
4.  **Manual Lock Clearing:** Update `acg.sh` or `gcp.sh` to optionally detect and warn about stale locks if extraction fails.

---

## Impact

This bug blocks all `make up` and `make refresh` operations across both AWS and GCP providers. It requires manual intervention (`rm SingletonLock` and `pkill chrome`) to resolve, which increases user friction and breaks the "automated" experience.
