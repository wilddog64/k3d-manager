# Issue: ACG Credentials Extraction Failures and Auth Dir Synchronization

**Date:** 2026-04-03
**Branch:** `k3d-manager-v1.0.2`

## Problem
The `acg_get_credentials` process encountered multiple failures during the v1.0.2 E2E verification task, primarily due to authentication state mismatch and timing issues on the Pluralsight platform.

## Analysis

### 1. Isolated Profile (Auth Dir)
- **Root Cause:** The script uses a dedicated Playwright persistent context at `~/.local/share/k3d-manager/playwright-auth/`.
- **Symptom:** Even if the user is signed into their main Chrome profile, this isolated profile starts unauthenticated, triggering redirects to the Pluralsight login page.
- **Impact:** Requires a one-time manual sign-in within the automated Chrome window to seed the persistent context.

### 2. Immediate Extraction Failures (Timing)
- **Symptom:** The script reported "extraction failed" almost immediately despite the user attempting to sign in.
- **Root Cause:** 
    - Initial timeouts for `isVisible` checks were too low (3s).
    - If the page began a redirect to `https://app.pluralsight.com/id` during the check, buttons like "Start Sandbox" were reported as not visible, causing the script to skip the start flow and attempt extraction from empty inputs.
- **Solution Applied:** Increased sign-in detection and completion timeouts to 10s and 300s respectively.

### 3. "Empty Boxes" State
- **Symptom:** "Inputs found: 4, Credentials not found" (observed in debug probes).
- **Diagnosis:** The "Start Sandbox" button was present but not clicked, or clicked but the platform had not yet populated the copyable inputs with AWS keys. 
- **Impact:** The script correctly identifies these as empty but needs sufficient waiting logic (currently 60s) to allow the platform to generate the keys.

## Recommended Follow-up
1. **Bootstrap Documentation:** Document the mandatory "One-time manual sign-in" requirement for fresh environments.
2. **Handle Redirects Better:** Improve the script to detect and wait for the `/id` login redirect loop before attempting to locate sandbox buttons.
3. **Environment Assist:** Encourage setting `PLURALSIGHT_EMAIL` to help the script auto-fill the login form.

## Impact
This issue blocked the completion of the `vault-bridge` E2E test as valid AWS credentials could not be reliably extracted to provision the infrastructure.
