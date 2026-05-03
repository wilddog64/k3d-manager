# Bug: Chrome SingletonLock Collision blocks automation launch

**Date:** 2026-05-02
**Severity:** High — blocks `acg_get_credentials` and watcher
**Status:** Fixed
**Assignee:** Gemini CLI

## Symptom
Automation fails to launch with the following error:
```
ERROR:chrome/browser/process_singleton_posix.cc:345] Failed to create ${HOME}/.local/share/k3d-manager/profile/SingletonLock: File exists (17)
Failed to create a ProcessSingleton for your profile directory.
```
Followed by `net::ERR_ABORTED` in Playwright.

## Root Cause
Chrome prevents multiple instances from sharing the same user-data-directory (`--user-data-dir`). 
1. **Orphaned Processes:** A previous crash leaves a `SingletonLock` symlink.
2. **Background Agents:** The `chrome-cdp` agent may be running, holding the lock.

## Required Fix
1. **Pre-flight Cleanup:** Add a check in `scripts/lib/cdp.sh` to remove a stale `SingletonLock` if no process is running.
2. **Process Guard:** Ensure the background agent is stopped before interactive automation attempts to take over the profile.

## Fix Applied

`scripts/lib/cdp.sh` now stops the Chrome CDP launchd agent before launching interactive automation and removes stale `SingletonLock` files only when the profile is not actively in use.
