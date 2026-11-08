# Bug: dashboard query test rejects a Bugs table column built by `label_replace`

**Status:** LANDED — test fix pushed on the release branch, 2026-11-08
**Priority:** P2
**Waiting on:** scheduled run — since 2026-11-08 (the next CI run on the release branch)
**Introduced by:** `bcf7b31d` (v1.43.15, Bugs table State check column)
**Should have been caught by:** offline test
**Severity:** medium — CI red on the release branch, which blocks the `deploy/hub` bootstrap (`make hub-promote` needs a CI-green commit)
**Approval:** operator, 2026-11-08 (bootstrap plan: "if pytest fails, file the bug and push only the test fix")
**Filed:** 2026-11-08
**Detected by:** Claude predicted it before CI ran; CI run 42478234554 on `f454ad13` confirmed it
**Affected:** `scripts/tests/bin/test_dashboard_queries.py` (`test_every_bug_dashboard_target_matches_producer_series`)
**Branch:** `k3d-manager-v1.43.15`

## Symptom

CI run 42478234554, `f454ad13`, step "Run pytest suites (hermes + bin)": 1 failed, 1918 passed, 4 skipped.

    FAILED scripts/tests/bin/test_dashboard_queries.py::test_every_bug_dashboard_target_matches_producer_series
    AssertionError: Bugs table columns absent from producer series: {'state_check'}

## Root cause

`bcf7b31d` added the Bugs table column `state_check`. It is built in the query by `label_replace`, not exported
by any producer. The test required every visible column to be a producer label. `bcf7b31d` was committed after
the last green CI (`011ba046`), and the pytest step had not run on the branch since, so the red went unseen until
this run.

## Fix

The test also accepts a column that the panel's own query creates with
`label_replace(..., "<name>", "<replacement>", "<src>", "<regex>")`. A column that is neither exported nor built
still fails.

## Evidence (offline, Claude's M4 session, 2026-11-08)

- `pytest scripts/tests/bin/test_dashboard_queries.py` → 3 passed
- mutant: a `bogus_col` column added to the Bugs table with no producer and no `label_replace` → the test fails;
  the dashboard file was restored and checked with `cmp`
