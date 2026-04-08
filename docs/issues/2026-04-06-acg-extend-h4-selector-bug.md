# Issue: acg_extend clicks non-interactive H4 header instead of button

## Status
**Identified** (Bugfix Pending)

## Description
The `acg_extend.js` script successfully identifies that the extension window is open but fails to actually extend the sandbox. The logs show:
```
INFO: Found extend button with selector: h4:has-text("Extend Your Session")
WARN: Could not confirm extension via toast/TTL text — proceeding anyway
```
After this, the `acg_watch` loop waits, the TTL naturally expires, and the instance is deleted, resulting in the `Instance gone — watcher stopping.` error.

## Root Cause
The `extendSelectors` array in `acg_extend.js` contains non-button, generic text selectors (e.g., `h4:has-text("Extend Your Session")`, `text="Extend Session"`). 
When the script runs, it finds the informational header text "Extend Your Session" on the main sandbox details card *before* it finds the actual "Extend Session" button inside the modal. Because the `for` loop breaks after finding the first visible match, it clicks the `h4` element (which has no action attached), erroneously believes it has succeeded, and exits.

## Impact
The script reports a successful extension when it has actually done nothing, causing the sandbox to eventually expire and the automated watcher to fail with an "Instance gone" error.

## Recommended Follow-up
1. Remove all non-interactive selectors from the `extendSelectors` array in `scripts/playwright/acg_extend.js`.
2. Specifically remove `h4:has-text(...)` and generic `text="..."` matchers.
3. Ensure the array only contains strict button selectors (e.g., `button:has-text(...)`, `[role="button"]`, `a`, and specific `[data-heap-id]` values).
