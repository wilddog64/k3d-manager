# Issue: lib-acg Chrome SingletonLock Collision

**Date:** 2026-05-02
**Severity:** High — blocks `make up` and automation launch
**Status:** Open
**Component:** `lib-acg`
**Assignee:** Gemini CLI

## Symptom
Automation fails to launch with the following error in the terminal:
```
ERROR:chrome/browser/process_singleton_posix.cc:345] Failed to create /Users/cliang/.local/share/k3d-manager/profile/SingletonLock: File exists (17)
Failed to create a ProcessSingleton for your profile directory.
```
Followed by `net::ERR_ABORTED` in Playwright.

## Root Cause
Chrome prevents multiple instances from sharing the same user-data-directory (`--user-data-dir`). 
1. **Orphaned Processes:** A previous crash or ungraceful shutdown leaves a `SingletonLock` symlink in the profile directory.
2. **Background Agents:** The `chrome-cdp` launchd agent may already be running Chrome with the same profile, blocking the interactive/automation launch.
3. **Race Condition:** Rapidly restarting automation might attempt to launch a new instance before the previous one has fully released the lock.

## Impact
Users cannot provision clusters or refresh credentials until they manually `pkill` Chrome or `rm` the lock file.

## Required Fix (in lib-acg)
1. **Pre-flight Cleanup:** Add a check in `scripts/lib/acg/scripts/lib/cdp.sh` (or the launch entry point) to detect and remove a stale `SingletonLock` if no associated process is running.
2. **Process Guard:** Improve `acg_chrome_cdp_install` / `acg_chrome_cdp_uninstall` to ensure the background agent is stopped before interactive automation attempts to take over the profile.
3. **Retry Logic:** Add a retry loop for `net::ERR_ABORTED` during initial navigation.
