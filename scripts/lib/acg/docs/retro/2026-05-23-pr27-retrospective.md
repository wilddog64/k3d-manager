# Retrospective — PR #27 (fix/next-improvements-5)

**Date:** 2026-05-23
**Milestone:** Playwright automation reliability — toast dismiss, CDP, credential re-validation
**PR:** #27 — merged to main (`7c17da72`)
**Participants:** Claude, Copilot

## What Went Well

- **Architectural insight on DOM vs pointer overlap** — the root cause of the 420s hang was a toast-dismiss block inside `_waitForCredentials` polling loop that clicked an action button (not the close X) that navigated away from the credential panel. DOM queries are never blocked by visual overlays, so the dismiss was never needed there. Removing this block eliminated the 420s hang entirely.

- **Async timing fix captured the server response window** — the API response arrives 3–5 seconds after button click; the original 5s/3s timeout windows were too short. Fixed with a 2s pre-wait (to skip immediate false positives) + 15s/10s detection windows matching real server response timing.

- **CDP Browser lifecycle clarified** — `disconnect()` vs `close()` on CDP Browser: `connectOverCDP()` returns a Browser that only supports `close()`, not `disconnect()`. Wrapping the cleanup in try/catch and eventually switching to `close()` prevented silent failures.

- **Toast selector narrowed from `:has-text()` to Escape key** — the initial broad `:has-text('Session extended')` selector could match and click an action button before the close X in Pando toast layouts. Switched to Escape key (reliable, vendor-agnostic) + Playwright `addLocatorHandler` to dismiss during pointer actions.

- **Copilot caught the button-selection and disconnect issues** — Copilot's review identified the `button.first()` ambiguity (action before close X in Pando) and the missing guard on `_cdpBrowser.disconnect()` before we ran against a live provider.

## What Went Wrong

- **Toast dismissal logic was scattered across three scripts** — each script (credentials, extend, restart) had its own toast handling path; inconsistency led to multiple fix iterations. Should have consolidated to a single helper early.

- **No defensive selector anchoring in initial toast logic** — using `:has-text()` without narrowing to the close button's parent meant the toast selector could match unintended siblings. Should have validated against the actual DOM structure before committing.

- **`_waitForCredentials` toast-dismiss block was architecturally backward** — polling a credential input inside an async credential-extraction function should never block on a UI toast; the toast dismiss belonged in pointer-action handlers (where `addLocatorHandler` lives), not in the polling loop itself.

## Process Rules Added

| Rule | Context |
|------|---------|
| **Consolidate repeated patterns early** | Toast dismissal logic across three scripts should have been unified to a helper on first appearance. |
| **Validate selectors against actual DOM structure** | Never rely on a selector's text; inspect the real HTML to ensure close buttons are unambiguous. |
| **Distinguish polling loops from pointer-action handlers** | Async polling for state (credentials, buttons) must not block on UI overlays; overlay handling belongs in `addLocatorHandler`. |

## Decisions Made

- **Playwright `addLocatorHandler` is the canonical toast-dismiss pattern** — replaces DOM `evaluate()` and browser-level `evaluate()` paths. It's reliable, vendor-agnostic, and decouples toast handling from business logic.

- **Escape key is the universal close button** — more reliable than selector-based clicks in multi-vendor UI frameworks (Pando, custom toasts, browser-native modals).

- **Pre-wait + extended window is the timing fix for async responses** — wait 2s to skip false positives on slow networks, then extend the detection window to match server response time (15s/10s depending on path).

## Theme

PR #27 fixed the Playwright automation reliability bottleneck by separating concerns: async credential polling no longer blocks on UI overlays, toast dismissal is now handled exclusively in pointer-action handlers via `addLocatorHandler`, and the CDP cleanup path uses the correct Browser lifecycle method (`close()` not `disconnect()`). The 420s hang was a false-negative architecture problem, not a timing problem. Once the dismiss block was removed and async paths were given adequate windows (15s instead of 5s), the 14 inter-related bugs became a single coherent fix: toast visibility should never block automated workflows.
