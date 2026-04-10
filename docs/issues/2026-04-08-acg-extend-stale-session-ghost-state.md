# Issue: acg_extend fails due to stale "Ghost" session state

## Status
**Identified** (Fix Pending)

## Description
The `acg_extend.js` script fails when a sandbox session enters a "Ghost" state. In this state, the Pluralsight UI still displays AWS credentials (Access Key ID, etc.), but the "Extend Session" button is not rendered. This typically happens when the session has internally expired or become stale, but the page hasn't fully transitioned to a "Deleted" state.

The only way to recover and trigger the extension modal is to manually delete and restart the sandbox.

## Root Cause
1. **Conditional Rendering:** Pluralsight hides the "Extend Session" button if the session is internally flagged as stale, even if the credentials panel remains visible.
2. **Missing Recovery Flow:** The current script assumes that if credentials are visible, an "Extend" button must be present or revealable via a simple "Open" click. It lacks the logic to "Delete and Restart" to force the extension modal to appear.

## Recommended Fix: "Delete/Restart to Extend" Logic
Update `scripts/playwright/acg_extend.js` to handle the missing button during the critical window (< 60 mins):
1. **Initial Search:** Look for "Extend Session" button. If found, click and exit.
2. **Stale Detection:** If the button is missing AND the TTL is low (< 15 mins) OR the TTL calculation failed (Midnight bug):
    - Click **"Delete Sandbox"**.
    - Confirm the deletion in the modal.
    - Click **"Start Sandbox"**.
    - Wait for the "Extend Your Session" modal to appear (triggered by Pluralsight's "Welcome back" logic).
    - Click **"Extend Session"** in that modal.
3. **Date Wrap Fix:** Ensure "12:00 AM" is correctly calculated as "Midnight tomorrow" to prevent false-positive "expiring soon" triggers.
