# Bug: unused `textwrap` import in the spec-intent test fails CI lint

**Status:** LANDED — import removed on the release branch, 2026-11-08
**Priority:** P2
**Waiting on:** scheduled run — since 2026-11-08 (the next CI run on the release branch)
**Introduced by:** `f1bab51e` (v1.43.15, specs filed from 2026-11-08 need approved evidence intents)
**Should have been caught by:** offline test
**Severity:** medium — CI red on the release branch, which blocks the `deploy/hub` bootstrap (`make hub-promote` needs a CI-green commit)
**Approval:** operator, 2026-11-08 (bootstrap plan: fix CI reds, then promote)
**Filed:** 2026-11-08
**Detected by:** CI run 42479985975 on `84268ee6`
**Affected:** `scripts/tests/bin/test_spec_intent.py`
**Branch:** `k3d-manager-v1.43.15`

## Symptom

CI run 42479985975, step "Lint Python (pyflakes)":

    scripts/tests/bin/test_spec_intent.py:4:8  F401 `textwrap` imported but unused
    Found 1 error.
    make: *** [Makefile:1438: lint-python] Error 1

Every other step passed except "Validate manifests (kubeconform)", which was skipped after the failure.
The pytest step that failed in run 42478234554 now passes.

## Root cause

`f1bab51e` imported `textwrap` and never used it. The previous run (42478234554) failed earlier, at pytest, so
lint never reached it. Ruff is not installed on Claude's M4 session (`make lint-python` → "Ruff not found"), so
the lint could not run before the push.

## Fix

Remove the import.

## Evidence (offline, Claude's M4 session, 2026-11-08)

- `make lint-python RUFF=<scratch venv ruff==0.15.8>` → `All checks passed!` (whole working tree)
- `pytest scripts/tests/bin/test_spec_intent.py` → 12 passed
- `make validate-manifests` (the step CI skipped) → 85 valid, 0 invalid, 0 errors
