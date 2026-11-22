# Bug: unused `now` in the M2 project-verified test fails CI lint

**Status:** VERIFIED — `03b86250`, CI lint green on `4a52c22e` (run 44914316268, 2026-11-21), which contains the fix; no live step (test-only lint fix)
**Fix commit:** `03b86250`
**Priority:** P2
**Introduced by:** `467e1de0` (v1.45.0 plan 3, multi-project M2 bug metrics)
**Should have been caught by:** offline test
**Introducing change reviewed:** yes (Fable)
**Prior art:** docs/bugs/2026-11-08-spec-intent-test-unused-import-fails-ci-lint.md (exact-symptom precedent, read) — same class: Claude verified with the test suite but not `make lint-python`
**Approval:** operator, 2026-11-18 ("go ahead": Claude fixes the one line directly, no dispatch)
**Branch:** `k3d-manager-v1.45.0`

## Symptom

CI job `lint` red on every push since `467e1de0` (latest run 44415302153 on `df635ebb`): ruff F841
`Local variable now is assigned to but never used` at `scripts/tests/bin/test_vectordb_bug_metrics.py:2127`.
Red CI blocks `make hub-promote`, so the M2, plans-panel (`72b9b031`) and metrics-push (`795e101e`) live checks were stuck.

## Fix

Delete the unused assignment. The test sets its dates through `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE`, not `now`.

## Evidence

- Pre-fix tree: `make lint-python` with ruff 0.15.8 → `F841 ... Found 1 error.` Post-fix: `All checks passed!` (Claude, M4, 2026-11-18).
- `pytest -k project_verified_values` passes after the fix.
- E2 (live): CI green on the fix commit, all check-runs on the head SHA.
