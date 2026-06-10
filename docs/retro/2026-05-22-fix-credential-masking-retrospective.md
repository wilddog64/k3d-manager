# Retrospective: fix/credential-masking (PR #23)

**Date:** 2026-05-22  
**PR:** #23 (`fix/next-improvements`)  
**Merge SHA:** 48afc0a4  
**Status:** Merged to main  

---

## Summary

Two usability fixes addressing credential safety and output visibility. Credential masking closed a long-standing gap since v0.2.0; extraction visibility ensures real-time feedback during ACG provisioning.

**Theme:** Operational safety + observability. Users should never see credentials in plain text on terminal, and they should see what the script is doing while waiting.

---

## What Went Well

- **Copilot caught real issues** — locator divergence between Playwright CDN and file-based sources, CHANGELOG wording precision; all review threads resolved cleanly on first pass.
- **CI green on first attempt** — no test failures, lint clean, all fixtures passing.
- **Minimal changes** — both fixes are surgical: masking filter in `bin/acg-credential-test` (12-line change), extraction visibility in `playwright/acg_credentials.js` (5-line change).
- **Backward compatible** — no breaking changes to public functions or configuration.

---

## What Went Wrong

- **Fixes applied to wrong upstream first** — both fixes were initially applied to k3d-manager's subtree copy (`scripts/lib/acg/`) instead of lib-acg repo. Required manual revert in k3d-manager before submitting PR to lib-acg proper.
- **Credential masking gap undetected for releases** — vulnerability existed since v0.2.0 (November 2024); no pre-commit hook or output validation caught plaintext secrets in test runner output.

---

## Technical Decisions

### Credential Masking Strategy
Used `sed 's/=.*/=***/'` pattern in `_print_masked()`:
- Simple, no dependencies on key name or value structure
- Works identically for AWS (e.g., `AWS_SECRET_ACCESS_KEY=***`) and GCP (`SA_PRIVATE_KEY_B64=***`)
- Applies to all key=value pairs without conditional logic
- Intentionally conservative — masks everything after `=` to prevent accidental leakage

### Extraction Progress Visibility
Changed from `page.evaluate()` with `querySelector` to `inputs.first().evaluate()` in Playwright:
- Same-node guarantee — avoids race conditions where input element is replaced between `querySelector` and `evaluate()`
- Ensures progress messages appear in real time on stdout instead of buffering
- No performance impact; more predictable and debuggable

---

## Theme: Safety and Observability

Two related principles:
1. **Operational Safety** — credentials should never appear in plain text, even in logs or REPL output. Users who run `set -x` or `bash -x` for debugging should still not leak secrets.
2. **Observability Without Noise** — long-running operations (Playwright automation, cloud provisioning) should emit progress messages so the user sees activity. Silence = uncertainty = user tries to interrupt.

This release prioritizes both by default.

---

## Outstanding

None. PR #23 is merged. Next feature branch (`fix/next-improvements-2`) created and ready for follow-up fixes.

