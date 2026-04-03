# Issue: Race Condition in Sandbox Start/Open Detection

**Date:** 2026-04-03
**Branch:** `k3d-manager-v1.0.2`

## Problem
The `acg_credentials.js` script frequently skips the "Start Sandbox" interaction, even when the button is visible to the user. This results in the script attempting to extract credentials from unpopulated fields, leading to extraction failure.

## Analysis

### 1. Root Cause: Race Condition
- **Logic:** The script uses `isVisible({ timeout: 5000 })` to check for "Start Sandbox", "Open Sandbox", and "Resume Sandbox" buttons sequentially.
- **Behavior:** On the Pluralsight Single Page App (SPA), the main dashboard skeleton loads first, but the specific sandbox cards (containing the buttons) are rendered dynamically.
- **The Failure:** If the script executes its `isVisible` checks before the cards have finished rendering, all checks return `false`. The script then incorrectly concludes that the buttons aren't needed and moves immediately to the "Extract credentials" phase.

### 2. Verified Facts (via CDP Probes)
- **Button Existence:** Confirmed that a button with exact text `"Start Sandbox"` is present in the main frame.
- **Visibility:** Confirmed the button is not obstructed by any overlays or drawers.
- **Script State:** API logs show the script completes its visibility checks and moves to `page.waitForSelector('input[aria-label="Copyable input"]')` while the sandbox is still in a "Startable" state (not yet running).

### 3. Impact
- **Extraction Failure:** Since the button is never clicked, the AWS credentials never populate.
- **Timeout:** The script eventually times out or fails at the `waitForSelector` step because the copyable inputs are tied to an active sandbox session.

## Recommended Fix
Replace the sequential `isVisible` checks with a unified `waitForSelector` or `Promise.race` pattern that waits for the page to reach any valid "interaction-ready" state.

### Suggested Implementation:
```javascript
// Define locators for all possible interaction targets
const interactionTargets = [
  page.locator('button:has-text("Start Sandbox")').first(),
  page.locator('button:has-text("Open Sandbox")').first(),
  page.locator('button:has-text("Resume")').first(),
  // Check for populated credentials (terminal state)
  page.locator('input[aria-label="Copyable input"]').first()
];

console.error('INFO: Waiting for dashboard to render (up to 30s)...');

// Wait for at least one of the above to be visible and stable
await page.waitForFunction((selectors) => {
  return selectors.some(s => {
    const el = document.querySelector(s);
    if (!el) return false;
    const style = window.getComputedStyle(el);
    return style && style.display !== 'none' && style.visibility !== 'hidden' && el.offsetWidth > 0;
  });
}, [
  'button:has-text("Start Sandbox")', 
  'button:has-text("Open Sandbox")', 
  'button:has-text("Resume")',
  'input[aria-label="Copyable input"]'
], { timeout: 30000 });

// Now proceed with logic based on which one is actually visible
if (await startButton.isVisible()) {
  // ... click logic ...
}
```

By waiting for the *existence* of any of these elements before deciding what to do, we eliminate the race condition where the script assumes the dashboard is "done" when it has only just begun to render.

## Current Status
- **Temporary Workaround:** User must manually click "Start Sandbox" if the script moves too fast.
- **Timeouts:** Script timeouts have been increased to 10m to allow for manual login, but the logic error remains.
