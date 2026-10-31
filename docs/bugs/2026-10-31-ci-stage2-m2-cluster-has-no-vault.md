# Bug: CI `stage2` cannot pass — the M2's CI cluster has no Vault

**Status:** FIXED — stage2 retired (landed from `2d0aa1b2`); live E3 (PR #153 run) pending
**Priority:** P3
**Approval:** operator, 2026-10-31 (filing: "go ahead for 1 and 2"; fix: "Retire stage2", "fix them so we
have a clean release")
**Filed:** 2026-10-31
**Detected by:** Claude, on PR #153 (v1.43.12) after adding the `ci:cluster-tests` label
**Affected:** `.github/workflows/ci.yml` jobs `detect` and `stage2`; `scripts/ci/runner_lock.sh`;
`scripts/tests/lib/runner_lock.bats`; `docs/howto/cloud-session-requests.md`
**Branch:** `k3d-manager-v1.43.12`
**Related:** `docs/bugs/archive/2026-08-20-pre-v1.26/2026-05-01-stage2-ci-always-fails-in-pr-context.md`
(same symptom; its fix put `stage2` behind the label, which hid the job but never made it pass);
`docs/bugs/2026-10-30-ci-stage2-ignores-m2-e2e-runner-lock.md` (superseded by this fix)

## Observed failure

PR #153, run 41219552067:

- Attempt 1: `ERROR: API server unreachable after 3 attempts`. OrbStack on the M2 was `Stopped`. Claude ran
  `orb start` (operator go); `readyz` then returned `ok` and the three agent nodes were `Ready`.
- Attempt 2: `ERROR: StatefulSet vault pods not Ready in secrets`.

On the M2's `k3d-k3d-cluster` (read-only, 2026-10-31): `kubectl get statefulset -A` returns
`No resources found`. Namespace `secrets` holds only External Secrets; there is no Vault anywhere.

Of the last ~10 CI runs where `stage2` started, none passed: every earlier one was cancelled by a newer
push. The release went out on the offline suites; the label was removed from PR #153 (operator go).

## Root cause

`stage2` depends on a long-lived cluster that nothing else uses and nothing checks. Between labelled PRs it
drifts (Vault gone, OrbStack stopped), and the drift is only seen when someone labels a PR. Provisioning
Vault again would only reset the clock. The remote e2e on the M2 (`make e2e-remote RUNNER=m2`,
`scripts/plugins/e2e_remote.sh`) already builds its own cluster for every run and is the live test path.

## Fix — retire `stage2` (operator decision, 2026-10-31)

1. `.github/workflows/ci.yml`: delete the `stage2` job, and the `detect` job (its only output,
   `skip_cluster`, feeds `stage2` alone). No other job may `needs:` either. No job keeps `runs-on` with
   `self-hosted`.
2. Delete `scripts/ci/runner_lock.sh` and `scripts/tests/lib/runner_lock.bats`; only `stage2` used them.
   `e2e_remote.sh` has its own lock functions; do not touch them.
3. Keep `scripts/ci/check_cluster_health.sh` and `bin/setup-mac-ci-runner` (the setup script still calls the
   health check). Do not touch them.
4. `docs/howto/cloud-session-requests.md` (~line 191): remove the sentence about CI `stage2` taking the lock;
   say remote e2e is the only user of the M2 runner lock.
5. Search `docs/` (excluding `docs/bugs/`, `docs/issues/`, `docs/plans/`, `docs/calibration/` history),
   `README.md` and `.github/` for `stage2` and `ci:cluster-tests`; update any doc that tells a reader to
   use them.
6. Add a test, `scripts/tests/lib/ci_workflow_no_stage2.bats`, that parses `ci.yml` (python3 + yaml, as
   `runner_lock.bats` did) and asserts: no `stage2` or `detect` job; no job runs on `self-hosted`; the string
   `ci:cluster-tests` does not appear.
7. Mark `docs/bugs/2026-10-30-ci-stage2-ignores-m2-e2e-runner-lock.md` **Status:** `SUPERSEDED — stage2
   retired (docs/bugs/2026-10-31-ci-stage2-m2-cluster-has-no-vault.md)`.
8. `CHANGELOG.md`: add a `### Removed` entry under the v1.43.12 section.

## Files

- `.github/workflows/ci.yml`
- `scripts/ci/runner_lock.sh` (delete)
- `scripts/tests/lib/runner_lock.bats` (delete)
- `scripts/tests/lib/ci_workflow_no_stage2.bats` (new)
- `docs/howto/cloud-session-requests.md`
- `docs/bugs/2026-10-30-ci-stage2-ignores-m2-e2e-runner-lock.md`
- `CHANGELOG.md`

## What NOT to do

- Do not provision Vault on the M2, and do not unregister the M2 Actions runner (operator, later).
- Do not change `scripts/plugins/e2e_remote.sh`.

## Acceptance

```yaml
must:
  M1: ci.yml has no stage2 job and no detect job, and every remaining job's needs list names only jobs that exist
  M2: scripts/ci/runner_lock.sh and scripts/tests/lib/runner_lock.bats are gone, and nothing outside docs history references runner_lock.sh
  M3: the cloud-session-requests how-to no longer says CI stage2 takes the M2 runner lock
  M4: the remaining ci.yml jobs (alertmanager-behaviour, lint) are unchanged
must_not:
  N1: no job in ci.yml runs on a self-hosted runner
  N2: the label ci:cluster-tests does not appear in ci.yml
evidence:
  E1:
    proves: [M1, N1, N2]
    kind: offline
    intent: >-
      You will see the new workflow test pass on the fixed ci.yml and fail on the pre-fix ci.yml (it still has
      stage2). It failed if it passes on both.
    what: bats scripts/tests/lib/ci_workflow_no_stage2.bats, run against HEAD and against git show HEAD~:.github/workflows/ci.yml
  E2:
    proves: [M2, M3, M4]
    kind: offline
    intent: >-
      You will see no runner_lock.sh references left outside docs history, and a diff of ci.yml that only
      removes the two jobs. It failed if anything else in ci.yml changed.
    what: grep -rn runner_lock.sh excluding docs/bugs docs/issues docs/plans; git diff of ci.yml
  E3:
    proves: [M1]
    kind: live
    intent: >-
      You will see PR #153's CI run with only alertmanager-behaviour and lint, both green. It failed if a
      stage2 or detect job appears.
    what: Claude reads gh run view for the PR's next run
interface:
  - .github/workflows/ci.yml
  - scripts/tests/lib/ci_workflow_no_stage2.bats
```

**Intent approved:** pending
