# Issue: `acg-up` bats test has stale step-number grep expectations

**Date:** 2026-05-16
**Scope:** Verification-only follow-up
**Related command:** `bats scripts/tests/bin/acg_up.bats`

---

## What Was Tested

Ran the focused `acg-up` bats suite after patching `scripts/lib/acg/playwright/acg_credentials.js`.

## Actual Output

```text
1..2
not ok 1 acg-up sources the Argo CD plugin before readiness checks
# (in test file scripts/tests/bin/acg_up.bats, line 97)
#   `[ "$status" -eq 0 ]' failed
ok 2 acg-up preserves existing Vault identity secrets on rebuild
```

## Root Cause

The failing assertion is a stale grep expectation in `scripts/tests/bin/acg_up.bats`. The test still looks for the literal string `Step 10e/14 — Installing Keycloak browser HTTP listener`, but the current `bin/acg-up` output uses the updated step numbering/text around that section.

## Recommended Follow-up

Update `scripts/tests/bin/acg_up.bats` to match the current `bin/acg-up` step text, or relax the assertion to check the functional content instead of the exact step number.
