# Issue: ACG Watcher fails to find "Extend" button

**Date:** 2026-04-29
**Severity:** Medium — leads to sandbox expiration if not caught manually
**Status:** Open
**Assignee:** Gemini CLI

## Symptom
The sandbox watcher log reports: `ERROR: Extend button not found or not visible after multiple attempts`. It fails to extend the session even when the 1h window is active.

## Root Cause (Suspected)
The Playwright script (likely in `lib-acg`) is unable to locate the "Extend" button after clicking "Open Sandbox". This can be caused by:
1.  **UI Change:** Pluralsight may have changed the CSS selectors or the nesting of the "Extend" button.
2.  **Timing/Race Condition:** The modal (Image 6) might be taking longer to appear than the script allows.
3.  **Mis-targeting:** The script might be clicking the "Delete Sandbox" button or another element by mistake due to ambiguous selectors.

## Required Sequence (as verified manually)
1. Click **Open Sandbox** on the running sandbox card.
2. Wait for the **Extend Your Session** modal to appear.
3. Click the **Extend Session** button in the modal.
4. Verify the **Session extended** toast/modal appears.

## Resolution Plan
1. Audit the extension logic in `lib-acg` (specifically the Playwright selectors).
2. Increase wait times for the extension modal.
3. Add a screenshot capture on failure to `lib-acg` to debug the exact state of the UI when it fails.
