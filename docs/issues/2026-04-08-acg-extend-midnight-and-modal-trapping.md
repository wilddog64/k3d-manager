# Issue: acg_extend Midnight Calculation and Modal Trapping

## Status
**Identified** (Fix Pending)

## Description
The `acg_extend.js` script fails in two specific scenarios identified via user screenshots:
1. **Midnight Boundary:** When the sandbox "Auto Shutdown" is at `12:00 AM`, the script calculates a negative TTL (e.g., -278 minutes) because it compares the time to "today" instead of "tomorrow."
2. **Modal Trapping:** If the "Extend Your Session" modal is already open (e.g., after a manual sandbox restart), the script's attempt to click the background "Open Sandbox" button fails or the TTL parsing logic is obstructed by the modal overlay.

## Root Cause
1. **Date Logic:** The parsing logic `shutdownTime.setHours(hours, mins, 0, 0)` does not account for the date. If the result is in the past, it should increment the date by 1.
2. **Execution Order:** The script parses TTL *before* checking for an already-visible "Extend Session" button. This makes it vulnerable to parsing errors even when the solution (the button) is already on screen.

## Recommended Fix
1. **Invert Logic:** Check for the "Extend Session" button immediately upon page load. If found, click and exit.
2. **Date Wrap-around:** Add `if (shutdownTime < now) shutdownTime.setDate(shutdownTime.getDate() + 1)` to the parsing logic.
3. **Selector Priority:** Ensure `button:has-text("Extend Session")` is the absolute first priority.
