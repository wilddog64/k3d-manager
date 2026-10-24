# Bug: CI's PromQL-evaluating pytest tests fail because the tripwire blocks `docker run`

**Status:** FIXED — pending the v1.43.5 PR CI run
**Priority:** P1 — `lint` fails on every PR from this branch, so the release can't pass the CI gate
**Severity:** high
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Filed:** 2026-10-24, by Claude, from PR #148 CI run 40120581806
**Approval:** fix under the operator's 2026-10-24 instruction to open the v1.43.5 PR; CI-only change
**Component:** `.github/workflows/ci.yml` (`lint` job)
**Related:** `docs/bugs/2026-10-23-dashboard-queries-untested-against-metric-labels.md`, `docs/bugs/2026-10-24-ci-lint-visudo-rejects-sudoers-on-ubuntu-26-04.md`

## Symptom

Two failures, both from promtool run through Docker and blocked by the tripwire's `docker` shim (rc 97):

- `test_dashboard_queries.py::test_every_bug_dashboard_target_matches_producer_series`
- `test_dispatch_metrics.py::test_by_model_promql_returns_one_series_per_model`

## Root cause

Both tests use a local `promtool` when one is on PATH and fall back to `docker run --entrypoint=promtool`.
The CI runner has no `promtool`, and the tripwire (correctly) blocks `docker run`. CI runs only on
PRs, so this release branch had never run the by-model test in CI.

## Fix

The `lint` job installs `promtool` 3.1.0 (the image version the tests pin) from the Prometheus
release tarball, checks it against the release's sha256, and puts it on PATH. The tripwire is
unchanged, and `promtool` isn't one of the tools it shims.

## Acceptance

```yaml
must:
  - id: M1
    text: Both PromQL tests run in CI with a real promtool and pass.
must_not:
  - id: N1
    text: The tripwire must not be loosened to allow docker run, and neither test may skip in CI.
evidence:
  - id: E1
    kind: offline
    proves: [M1]
    text: The step's script, run in ubuntu:24.04, verifies the checksum and promtool --version reports 3.1.0.
  - id: E2
    kind: live
    proves: [M1, N1]
    text: PR #148's lint job shows both tests passed, not skipped, with tripwire.sh unchanged in the diff.
interface:
  - .github/workflows/ci.yml lint job
```
