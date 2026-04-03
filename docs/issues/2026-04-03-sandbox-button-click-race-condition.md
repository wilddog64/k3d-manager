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

## Recommended Fix (For Codex/Future Task)
- Replace `isVisible` sequential checks with a race-condition-safe pattern.
- Use `page.waitForSelector` or a combined locator that waits for **any** of the interaction buttons (Start/Open/Resume) OR the populated credential inputs to appear.
- Ensure the script stays on the "Interaction" phase until one of these states is definitively reached.

## Current Status
- **Temporary Workaround:** User must manually click "Start Sandbox" if the script moves too fast.
- **Timeouts:** Script timeouts have been increased to 10m to allow for manual login, but the logic error remains.
