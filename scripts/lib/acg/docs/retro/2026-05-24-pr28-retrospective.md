# Retrospective — PR #28

**Date:** 2026-05-24
**Milestone:** fix/next-improvements-6 — false-positive "Extend Your Session" dialog detection
**PR:** #28 — merged to main (`ee87aeb2f088c873c1937f9b5bb2e5eb495b3094`)
**Participants:** Claude, Copilot

## What Went Well

- Root cause was correctly identified: Pluralsight SPA keeps dialog in DOM permanently; `visibility:hidden` does not prevent `innerText` from returning non-empty text, requiring a three-part guard
- Copilot caught two gaps: (1) `_waitForSandboxEntry` `hasExtendDialog` predicate had no guard at all; (2) `acg_restart.js` was missing `visibility !== 'hidden'` despite the bug doc claiming parity
- All three Copilot threads were replied to and resolved via GraphQL in the same session
- Bug doc (`docs/bugs/2026-05-24-acg-credentials-false-positive-extend-dialog.md`) was written alongside the fix

## What Went Wrong

- Direct subtree edit attempted first (editing k3d-manager's `scripts/lib/acg/` copy directly) — caught and reverted; correct path is lib-acg upstream → PR → subtree pull
- Bug doc initially claimed `acg_restart.js` already had the three-part guard, but it only had two parts — doc was inaccurate

## Process Rules Added

| Rule | File |
|------|------|
| Narrowed `addLocatorHandler` rule to toast/overlay dismissal only | `.github/copilot-instructions.md` |
| Modal dialog dismissal via `page.evaluate()` DOM clicks is intentional (Escape closes sandbox panel) | `.github/copilot-instructions.md` |

## Decisions Made

- Three-part visibility guard (`offsetParent !== null && getComputedStyle(d).display !== 'none' && getComputedStyle(d).visibility !== 'hidden'`) is now the standard across all files
- lib-acg subtree edits must always go upstream first — never edit `scripts/lib/acg/` in k3d-manager directly

## Theme

A quick-seeming one-liner fix (add visibility guard) turned into a three-file audit: the guard was missing in a third location in `acg_credentials.js`, `acg_restart.js` didn't actually match what the bug doc claimed, and the copilot-instructions conflicted with the intentional DOM-click pattern for modal dialogs. Copilot's review caught all three gaps in a single pass.
