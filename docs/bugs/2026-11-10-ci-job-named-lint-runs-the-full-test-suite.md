# Bug: the CI job named `lint` runs the full offline test suite

**Status:** OPEN
**Priority:** P3
**Waiting on:** operator decision — since 2026-11-10 (intent approval)
**Introduced by:** unknown (the test steps accreted into `lint` over several releases)
**Should have been caught by:** review
**Prior art:** exact-slug glob: none. `make find-similar-docs` unavailable (vector store: context `k3d-k3d-cluster` does not exist on the M4, 2026-11-10). Related, not a duplicate: `docs/plans/v1.44.0-parallel-offline-tests.md` (local runner speed; leaves CI unchanged, line 62)
**Severity:** misleading, no breakage. A "lint" result takes 20.8 min and a red `lint` usually means a failing test,
not a lint finding. Lint feedback that could arrive in about a minute waits behind the suite.
**Approval:** operator, 2026-11-10: "so then we should really make the name correctly reflect what it does"
**Filed:** 2026-11-10
**Detected by:** operator, reading the PR-checks dashboard (lint 20.8 min)
**Branch:** `k3d-manager-v1.43.15`

## Evidence (Claude, 2026-11-10, CI run `42908743867` on `k3d-manager-v1.43.15`)

Steps of job `lint` (`.github/workflows/ci.yml:35`), timed from `gh run view --json jobs`:

| Step | Time |
|---|---|
| Run the full offline suite (BATS + Python), `make test` (`:112-120`) | 866 s |
| Run pytest suites (hermes + bin), `make test-pytest` (`:130-134`) | 144 s |
| shellcheck, pyflakes, yamllint, kubeconform, setup | about 35 s |

## Fix

Split job `lint` in `.github/workflows/ci.yml` into two jobs on the same triggers:

- `lint`: checkout, setup the lint needs, shellcheck, pyflakes (`make lint-python`), yamllint, kubeconform. No test step.
- `test`: checkout, the setup the suites need (promtool, pytest, Copilot CLI and its env), `make test`, `make test-pytest`.

Both jobs keep `permissions: contents: read` and pinned action tags. No test is added, removed or skipped; the step
commands stay byte-identical, only their job moves. Parallel sharding is out of scope (an idea row, not this fix).

## Contract readers

- Job name `lint` as a GitHub check name: readers found by grep and the API, 2026-11-10:
  - Branch protection: ruleset `main` (id 12967352) has only `deletion` and `non_fast_forward` rules, no required
    status checks; classic protection has none (`required_status_checks` contexts `[]`). Unchanged.
  - PR-checks exporter and `scripts/etc/argocd/platform-ops/grafana-dashboard-pr-checks.yaml`: group by the `check`
    label, no hard-coded name. Changes in meaning: after the split `lint` durations drop to about 1 min and a new
    `test` series appears; history before the change keeps the suite under `lint`. Note it in the dashboard panel
    description.
  - `scripts/tests/hermes/test_pr_checks.py:15-91` and `scripts/tests/plugins/grafana_dashboard_pr_checks.bats:221-233`:
    use `"lint"` as sample fixture data only. Unchanged.
- Writer: `.github/workflows/ci.yml` is the only writer of the check name.

## Acceptance

```yaml
must:
  - id: M1
    text: "CI has a job named lint that runs only the lint steps (shellcheck, pyflakes, yamllint, kubeconform) and a job named test that runs make test and make test-pytest."
  - id: M2
    text: "Every step command that ran in the old lint job runs in exactly one of the two new jobs, unchanged."
must_not:
  - id: N1
    text: "The lint job never runs make test or make test-pytest."
  - id: N2
    text: "No test step is dropped, skipped or made non-blocking by the split."
evidence:
  - {id: E1, proves: [M1, M2, N1, N2], kind: offline, intent: "You will see a test parse ci.yml and fail if the lint job runs make test or make test-pytest, or if any step command from the old job is missing from both new jobs or marked continue-on-error; it fails on today's ci.yml."}
  - {id: E2, proves: [M1], kind: live, intent: "Claude shows the first CI run after the change on GitHub: a lint check finishing in a few minutes and a separate test check running the suites, both green."}
interface:
  - ".github/workflows/ci.yml"
  - "GitHub check names on a push to the release branch"
```

## Worker definition of done

- Change only `.github/workflows/ci.yml`, a new or existing static test under `scripts/tests/`, and the PR-checks
  dashboard panel description. Show E1 red on today's `ci.yml`, then green. Paste command, rc and proving lines.
  Leave changes uncommitted; Claude reviews and lands.
