# Bug: Google account mismatch blocks OAuth callback

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/playwright/gcp_login.js`

---

## Summary

Although the Playwright robot successfully clicks through the "Choose an account" and "Allow" screens, the `gcloud auth login` command in the terminal never receives the authentication token. The browser reports success, but the CLI remains unauthenticated.

---

## Reproduction Steps

1. Start a fresh GCP sandbox.
2. Run `CLUSTER_PROVIDER=k3s-gcp make up`.
3. Observe the robot clicking an old "Signed out" account in the Google menu.
4. Observe the browser reporting success.
5. Run `gcloud auth list`.
6. Observe that the new account is NOT listed, or is listed with "No valid credentials."

---

## Root Cause

When multiple stale accounts are present in the browser's "Choose an account" list, clicking an existing account often fails to trigger the localhost redirect that `gcloud` expects. The robot is clicking a "Ghost" session instead of performing a fresh authentication.

---

## Proposed Fix

Implement a **"Clean Slate" login pattern**:
1.  **Force Sign-out:** Before starting the OAuth flow, the robot should navigate to `https://accounts.google.com/Logout` to clear all stale "Signed out" accounts.
2.  **Explicit Login:** Use the "Use another account" path every time to force a fresh entry of the extracted email and password.
3.  **Single Session:** This ensures Google treats the session as a fresh grant and correctly sends the code back to the terminal.

---

## Impact

High. The identity switch is functionally broken for any user with a messy Chrome history, requiring manual `gcloud auth login` despite the automation.
