# Bug: CI `stage2` cannot pass — the M2's CI cluster has no Vault

**Status:** OPEN
**Priority:** P3
**Approval:** operator, 2026-10-31 (filing: "go ahead for 1 and 2"); fix approach pending
**Filed:** 2026-10-31
**Detected by:** Claude, on PR #153 (v1.43.12) after adding the `ci:cluster-tests` label
**Affected:** `.github/workflows/ci.yml` job `stage2`; `scripts/ci/check_cluster_health.sh`; the M2 runner's
`k3d-k3d-cluster`
**Branch:** `k3d-manager-v1.43.12` (filed); fix in a later release
**Related:** `docs/bugs/archive/2026-08-20-pre-v1.26/2026-05-01-stage2-ci-always-fails-in-pr-context.md`
(same symptom; its fix put `stage2` behind the label, which hides the job but does not make it pass);
`docs/bugs/2026-10-30-ci-stage2-ignores-m2-e2e-runner-lock.md` (its live E3 needs a passing `stage2`)

## Observed failure

PR #153, run 41219552067:

- Attempt 1: `ERROR: API server unreachable after 3 attempts`. OrbStack on the M2 was `Stopped`. Claude ran
  `orb start` (operator go); `readyz` then returned `ok` and the three agent nodes were `Ready`.
- Attempt 2: `ERROR: StatefulSet vault pods not Ready in secrets`.

On the M2's `k3d-k3d-cluster` (read-only, 2026-10-31): `kubectl get statefulset -A` returns
`No resources found`. Namespace `secrets` holds only External Secrets; there is no Vault anywhere. The
namespaces are `default`, `istio-system`, `istio-test-1775824381-15352` (a leftover from a test run 204
days ago), `kube-*` and `secrets`.

Of the last ~10 CI runs where `stage2` started, none passed: every earlier one was cancelled by a newer
push. So nothing has exercised this cluster for weeks, and the gap stayed hidden.

The release went out on the offline suites: the label was removed from PR #153 (operator go).

## Fix (to decide)

Either:

1. Provision Vault, and anything else `check_cluster_health.sh` and `test_vault`/`test_eso` expect, on the
   M2's CI cluster, idempotently from a make target, and have the health check name what is missing
   rather than wait for a StatefulSet that does not exist; or
2. Retire `stage2` in favour of the remote e2e on the M2 (`make e2e-remote RUNNER=m2`), which already
   builds its own cluster.

Also: the health check should fail in seconds with "no Vault StatefulSet in secrets" instead of waiting
for one, and delete the stale `istio-test-*` namespace.

## Acceptance

```yaml
must:
  M1: on a ci:cluster-tests PR, stage2's cluster health check passes on the M2 and the integration tests run
  M2: when Vault is absent, check_cluster_health.sh exits non-zero within 30s and names the missing StatefulSet
must_not:
  N1: check_cluster_health.sh never exits 0 when the secrets namespace has no Vault StatefulSet
evidence:
  E1:
    proves: [M2, N1]
    kind: offline
    intent: >-
      You will see the health-check test fail fast with "no Vault StatefulSet" against a stubbed cluster
      that has none. It failed if the check waits out its timeout or passes.
    what: bats with a kubectl stub captured from the M2 (statefulset list "No resources found")
  E2:
    proves: [M1]
    kind: live
    intent: >-
      You will see the stage2 job green on a labelled PR. It failed if stage2 is red or skipped.
    what: Claude labels a PR ci:cluster-tests and reads the stage2 log
interface:
  - scripts/ci/check_cluster_health.sh (KUBE_CONTEXT, KUBECTL)
  - .github/workflows/ci.yml job stage2
```

**Intent approved:** pending
