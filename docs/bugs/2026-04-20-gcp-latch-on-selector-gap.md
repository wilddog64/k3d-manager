# Bug: GCP latch-on script missing ToS and Profile selectors

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/playwright/gcp_login.js`

---

## Summary

The automated identity switch in `gcp_login` hangs on fresh sandboxes because the robot does not recognize the "Agree and continue" button (GCP Terms of Service) or the "Confirm" button (Chrome profile data handling).

---

## Root Cause

`scripts/playwright/gcp_login.js` currently only looks for "I agree", "Accept", and "Continue". Fresh ACG sandboxes present specific variations of these buttons that were not in the initial spec.

---

## Proposed Fix

Add the following selectors to the state machine in `gcp_login.js`:
1. `button:has-text("Agree and continue")`
2. `button:has-text("Confirm")`
