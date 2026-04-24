# Bug: Start Sandbox Button Disabled Timeout (ACG AWS/GCP)

**Date:** 2026-04-23
**Status:** OPEN
**Severity:** CRITICAL (Blocker)

## Summary

The `acg-up` automation fails with a 30000ms timeout when attempting to click the "Start Sandbox" button. Playwright correctly identifies the button, but it is in a `disabled` state in the DOM.

## Terminal Output

```text
ERROR: locator.click: Timeout 30000ms exceeded.
Call log:
  - waiting for locator('button:has-text("Start Sandbox")').first()
    - locator resolved to <button disabled data-heap-id="Hands-on Playground - Click - AWS Sandbox - Start Sandbox" class="pando-w_[100%] pando-flex-g_1 sm:pando-w_fit lg:pando-flex-g_0 pando-button pando-button--palette_action pando-button--size_lg pando-button--usage_filled">…</button>
  - attempting click action
    2 × waiting for element to be visible, enabled and stable
      - element is not enabled
    - retrying click action
    - waiting 20ms
    2 × waiting for element to be visible, enabled and stable
      - element is not enabled
    - retrying click action
      - waiting 100ms
    56 × waiting for element to be visible, enabled and stable
       - element is not enabled
     - retrying click action
       - waiting 500ms

make: *** [up] Error 1
```

## Root Cause Analysis (RCA)

1. **State Machine Deadlock:** The automation script assumes the sandbox needs to be started and attempts to click the "Start Sandbox" button.
2. **Element State:** The button is found but has the `disabled` attribute. 
3. **Trigger Scenarios:**
   - **Sandbox Already Provisioned:** The sandbox is already running, and the "Start Sandbox" button is disabled by the ACG application in favor of "Open Console" or "Clear Sandbox".
   - **Provisioning Lag:** The UI is in a transient state where the button is visible but not yet interactable.
   - **Latching Failure:** `acg_credentials.js` or `acg_extend.js` does not check if the sandbox is already active before trying to start it.

## Recommended Fix

Update the automation to check for an already-active sandbox state before attempting to click "Start Sandbox". If the button is disabled, the script should look for "Open Console" or "Clear Sandbox" to confirm the environment is ready for latching.

## Files Implicated
- `scripts/playwright/acg_credentials.js`
- `scripts/playwright/acg_extend.js`
