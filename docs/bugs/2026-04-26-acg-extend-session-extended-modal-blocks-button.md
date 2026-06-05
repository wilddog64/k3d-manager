# Bug: `acg_extend` misses the extend surface when it appears late

**File:** `playwright/acg_extend.js`
**Branch:** `feat/acg-extend-modal-wait`
**Severity:** High — `acg_extend` can fail if the extend surface is slower than the fixed post-click sleep

---

## Symptom

```text
INFO: Already on Pluralsight page: https://app.pluralsight.com/hands-on/playground/cloud-sandboxes
INFO: Calculated remaining TTL: ~42 minutes
INFO: Within 1h extension window (42m remaining). Proceeding to extend...
INFO: Clicking Open Sandbox to reveal extend panel...
ERROR: Extend button not found or not visible after multiple attempts (including recovery)
```

The automation was relying on a fixed post-click sleep and then searching once for the extend button. In the live UI, the extend surface can take longer to appear, and a lingering `"Session extended"` confirmation modal can also still be present from the previous run.

---

## Root Cause

`extendSandbox()` needs to handle both of these states before it can safely extend again:
1. dismiss any lingering `"Session extended"` confirmation modal
2. wait for the extend button / modal surface to appear after clicking **Open Sandbox**

---

## Fix

In `playwright/acg_extend.js`:
1. Dismiss any lingering `"Session extended"` confirmation modal before searching for the button.
2. Replace the fixed post-`Open Sandbox` sleep with an explicit polling loop for the extend button.
3. Capture a screenshot if the button still cannot be found after all attempts.

---

## Definition of Done

- [ ] Dismissal block added after the navigation guard
- [ ] Post-`Open Sandbox` wait uses an explicit polling loop instead of a fixed sleep
- [ ] `node --check playwright/acg_extend.js` passes with zero errors
- [ ] Committed on branch `feat/acg-extend-modal-wait` in lib-acg with message:
  `fix(acg-extend): wait for extend surface before searching for extend button`
- [ ] SHA reported; pushed to origin

## Historical Notes

- This fix was developed on `feat/acg-extend-modal-wait` and recorded in PR #3.
- The repo-level workflow in this issue doc is historical context from the original bug report, not a live restriction on follow-up documentation updates.
