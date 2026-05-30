# Retrospective — fix/next-improvements-4

**Date:** 2026-05-23  
**PR:** #26 — merged to main (`fbcecc24`)  
**Participants:** Claude, Codex, Copilot

## What Went Well

- Codex applied the visibility guard correctly to the detection path on first attempt (`offsetParent !== null && getComputedStyle(d).display !== 'none'`)
- Copilot caught the incomplete fix before merge: visibility guard was added to `_isExtendYourSessionVisible()` detection but missing from the `.find()` selection path within `_dismissExtendYourSessionDialog`
- `node --check` gate passed cleanly — no syntax errors across all modified Playwright files
- Issue doc convention (`docs/issues/`) followed correctly in the Copilot review findings

## What Went Wrong

- Fix was incomplete on first commit: visibility guard applied only to the `some()` detection predicate but not to the `.find()` selection predicate in the same function — this created a second-order bug where a hidden/display:none template node could still be selected for the dismiss click, causing the function to fail silently on the wrong element
- Bug spec `## Rules` section used "No other files touched" which contradicted the reality that CHANGELOG and memory-bank updates were required in the same PR

## Process Rules Added

| Rule | Context |
|------|---------|
| When adding visibility guards to browser-JS predicates, apply the guard to **all call sites that match on the same selector** in the same function (both detection and selection paths). A guard on the detector but not the selector creates a false-positive second-order bug. | Applied to `_dismissExtendYourSessionDialog` — both `some()` detection and `.find()` selection must check `offsetParent !== null && getComputedStyle(d).display !== 'none'` |
| Bug spec `## Rules` must use "Code change limited to `<file>`; CHANGELOG and memory-bank updates may also be required" — not "No other files touched". | lib-acg bug spec template update |

## Decisions Made

- **Visibility predicate for Pluralsight dialog detection:** `offsetParent !== null && getComputedStyle(d).display !== 'none'` — established as the canonical check for detecting whether the "Extend Your Session" dialog is actually visible. Reused in both `_isExtendYourSessionVisible` detection and the actual element selection path inside `_dismissExtendYourSessionDialog`. This guards against stale DOM references and CSS-hidden templates.

## Theme

This milestone fixed a subtle but impactful false positive in ACG sandbox automation: `acg_restart.js` was triggering the "Extend Your Session" dismiss path immediately after clicking Open Sandbox, even when no dialog was visible on the page. The root cause was a missing CSS visibility guard in the `.find()` DOM query that selects which element to dismiss. Codex applied the guard to the right detection path (`_isExtendYourSessionVisible`) but left the selection path unguarded — a second-order bug that Copilot caught during review. The process lesson: any PR that adds a CSS visibility guard to a predicate must apply it consistently to all uses of the same selector in the same scope, particularly when separating detection (test if visible) from selection (pick which one to act on).
