# Bug: ACG credential extraction lacks granular observability (Session Contract Gap)

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/playwright/acg_credentials.js`, `scripts/plugins/acg.sh`

---

## Summary

The current implementation of the "CDP/Session Contract" is partially blind. While the system no longer crashes or hijacks the browser, it fails to fulfill the observability requirements defined in the spec:

1.  **Shell Blindness:** The shell layer (`acg.sh`) cannot distinguish between a "Login Required" error and an "Unexpected Page" error. It only sees a generic exit code `1`.
2.  **Coarse Classification:** The Playwright script (`acg_credentials.js`) uses binary logic (Dashboard vs. Not Dashboard) instead of the required state matrix (Ready, Login Required, Loading, Unexpected Page).
3.  **Generic Timeouts:** Users still see generic "Timed out waiting for sandbox dashboard" messages even when the script has enough information to identify a specific blocker (like being stuck on a landing page).

---

## Root Cause

1.  **Missing Exit Code Contract:** `acg_credentials.js` does not use reserved exit codes to communicate specific session states back to the shell.
2.  **Coarse Polling Loop:** The polling loop in `acg_credentials.js` lacks a granular state machine to classify the current URL and page content into the four required contract states.
3.  **Delegation Gap:** `acg_get_credentials` in the shell does not yet implement the `case` logic to handle the third error class: "CDP reachable but session unusable."

---

## Proposed Fix

1.  **Implement Reserved Exit Codes:**
    *   `10`: `LOGIN_REQUIRED` (Session on `/id` or `/hands-on`)
    *   `11`: `UNEXPECTED_PAGE` (No relevant tabs found)
    *   `12`: `EXTRACTION_TIMEOUT` (Dashboard reached but creds missing)
2.  **Refactor JS Polling:** Replace the simple `if/else` in the polling loop with a state-classifier that identifies the specific page state on every tick.
3.  **Update Shell Dispatcher:** Implement explicit error messaging in `acg.sh` for each reserved exit code to provide actionable feedback to the user.

---

## Impact

This gap makes troubleshooting difficult. When the automation "hangs," the user cannot tell if it is waiting for them to sign in, if it is lost on a different tab, or if the Pluralsight UI has changed. It violates the "Explicit Failures" principle of the session contract.
