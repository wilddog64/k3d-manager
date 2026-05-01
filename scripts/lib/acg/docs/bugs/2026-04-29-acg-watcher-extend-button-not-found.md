# Bug: `acg_watch` / `acg_extend` fails to find "Extend" button

**Date:** 2026-04-29
**Severity:** Medium — sandbox expires if the watcher cannot extend in time
**Status:** Open
**Assignee:** Gemini CLI

## Symptom
The watcher logs:

```text
ERROR: Extend button not found or not visible after multiple attempts
```

Manual extension still works in the browser, so the UI is extendable, but the automation does not reach the final button consistently.

## Where the failure likely lives
The implementation path is:

- `scripts/plugins/acg.sh::_acg_extend_playwright` launches the Node script
- `scripts/plugins/acg.sh::acg_watch` calls `_acg_extend_playwright` on the timer
- `playwright/acg_extend.js` contains the actual browser search / click flow

The likely fix point is `playwright/acg_extend.js`, especially the flow that:

1. navigates or reuses the Pluralsight page
2. dismisses any modal state
3. clicks **Open Sandbox**
4. searches for **Extend Session**

## Verified manual sequence
The manual recovery path that works is:

1. Click **Open Sandbox** on the running sandbox card.
2. Wait for the **Extend Your Session** modal to appear.
3. Click **Extend Session**.
4. Verify the **Session extended** confirmation appears.

## Not yet proven
The repo does not yet prove which of these is failing:

1. A stale selector in `playwright/acg_extend.js`
2. A wait timing issue before the modal appears
3. Clicking the wrong sandbox card or a wrong button
4. A UI state mismatch that only appears during watcher execution

## Recommended next step
Add failure-time diagnostics in `playwright/acg_extend.js` so the DOM or screenshot at the point of failure can be compared against the manual flow.
