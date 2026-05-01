# Issue: ACG Watcher fails to find "Extend" button

**Date:** 2026-04-29
**Severity:** Medium — leads to sandbox expiration if not caught manually
**Status:** Open
**Assignee:** Gemini CLI

## Symptom
The sandbox watcher log reports: `ERROR: Extend button not found or not visible after multiple attempts`. The automation fails to extend the session even when the 1h window is active.

## What Is Verified
The manual recovery path works and requires the following sequence:
1. Click **Open Sandbox** on the running sandbox card.
2. Wait for the **Extend Your Session** modal to appear.
3. Click the **Extend Session** button in the modal.
4. Verify the **Session extended** toast/modal appears.

This confirms the session can be extended manually, but it does not yet prove which step the watcher is missing.

## What Is Not Yet Verified
The repo does not yet prove whether the failure is caused by:
1. A stale selector in the Playwright script.
2. A missing or insufficient wait for the modal to appear.
3. Clicking the wrong card or button on the sandbox list.
4. A UI state mismatch that only appears during watcher execution.

## Resolution Plan
1. Audit the extension logic in `lib-acg` (specifically the Playwright selectors and the state transition that precedes the modal).
2. Capture the DOM or a screenshot at the point of failure so the visible button set can be compared with the manual flow.
3. Increase wait times only if the modal is confirmed to exist but appears late.
4. If the UI now requires the sandbox details view before the modal appears, update the automation to explicitly open that view before searching for **Extend Session**.
