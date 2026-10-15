# Bug: make smoke uses obsolete ubuntu-k3s app prefix and silently targets M4 (2026-10-13)

**Status:** OPEN — root cause confirmed by live read-only ArgoCD inventory; fix not implemented
**Branch:** `k3d-manager-v1.43.2` (triage 2026-10-15, operator-approved placement)
**Priority:** P2 — false release-gate failures
**Release:** v1.43.2 (triage 2026-10-15, operator-approved placement)
**Filed:** 2026-10-13, at operator request
**Approval:** explicit 2026-10-13 "go ahead" (file bug; not approval to modify runtime)
**Component:** `bin/smoke-test-cluster-health`, `make smoke`
**Related:** `docs/bugs/2026-09-25-smoke-cluster-health-app-context-decoupled-from-app-prefix.md` (earlier recurrence, marked fixed in ff47bc2b)

## Observed failure

On M4, `make smoke` reports:

```
infra: k3d-k3d-cluster
app:   k3d-k3d-cluster
Infra context: k3d-k3d-cluster; app context: k3d-k3d-cluster (apps: ubuntu-k3s-shopping-cart-*)
[FAIL] ghcr-pull-secret MISSING in shopping-cart-apps
[FAIL] ghcr-pull-secret MISSING in shopping-cart-data
[FAIL] ghcr-pull-secret MISSING in shopping-cart-payment
[FAIL] shopping-cart-basket: NotFound (expected Synced)
[FAIL] shopping-cart-order: NotFound (expected Synced)
[FAIL] shopping-cart-payment: NotFound (expected Synced)
[FAIL] shopping-cart-product-catalog: NotFound (expected Synced)
[FAIL] shopping-cart-frontend: NotFound (expected Synced)
[FAIL] only 0/5 pods Running — expected 5
=== Result: 0 passed, 9 failed ===
```

The operator's read-only inventory showed all five actual application names exist and are `Synced`:

```
ubuntu-hostinger-shopping-cart-basket            Synced Healthy
ubuntu-hostinger-shopping-cart-order             Synced Healthy
ubuntu-hostinger-shopping-cart-payment           Synced Healthy
ubuntu-hostinger-shopping-cart-product-catalog   Synced Healthy
ubuntu-hostinger-shopping-cart-frontend          Synced Healthy
```

Their ArgoCD `spec.destination.name` is `ubuntu-hostinger`, and the local kubeconfig contains contexts `k3d-k3d-cluster` and `ubuntu-hostinger`. The app-prefix default is `ubuntu-k3s-`, so the script cannot find `ubuntu-k3s-shopping-cart-basket`. Its destination lookup then silently assigns `APP_CONTEXT=INFRA_CONTEXT`, making *all nine checks* run against irrelevant names and/or the wrong cluster. This is **not proof the Hostinger pods/secrets are healthy**: the explicitly targeted smoke run has not yet been supplied.

## Root cause in source

`bin/smoke-test-cluster-health` sets:
```bash
ARGOCD_APP_PREFIX="${ARGOCD_APP_PREFIX-ubuntu-k3s-}"
```
When `APP_CONTEXT` is unset, it queries `${ARGOCD_APP_PREFIX}shopping-cart-basket` and, on no result or unavailable context, falls back to `INFRA_CONTEXT`. The current inventory has *only* the `ubuntu-hostinger-` prefixed workload applications. The prior fix decoupled app context from infra context when the assumed app name existed; it did not eliminate obsolete name defaults or ambiguous/missing-target fallback.

## Reproduce / immediate read-only diagnostic

```bash
kubectl --context k3d-k3d-cluster -n cicd get applications \
  -o custom-columns=NAME:.metadata.name,DEST:.spec.destination.name,SYNC:.status.sync.status
kubectl config get-contexts
INFRA_CONTEXT=k3d-k3d-cluster APP_CONTEXT=ubuntu-hostinger \
  ARGOCD_APP_PREFIX=ubuntu-hostinger- bin/smoke-test-cluster-health
```
The final command still performs read-only smoke checks; record its actual result before claiming the target is healthy.

## Desired behavior

1. Resolve the intended shopping-cart target from actual ArgoCD Application/ApplicationSet inventory (or require an explicit runner/operator target when >1 eligible set). The matching applications must share a consistent destination. Never silently pick one arbitrarily.
2. When `ARGOCD_APP_PREFIX`/`APP_CONTEXT` are explicitly supplied, validate that application names and destination agree; do not silently redirect.
3. When no unambiguous eligible target exists, exit with an actionable **target-discovery error** listing safe candidate names/destinations; do not emit nine misleading app-health FAILs from `INFRA_CONTEXT` fallback.
4. Preserve the three secret checks, five ArgoCD checks and pod readiness check **after** target selection; do not weaken or skip real health failures.
5. Be compatible with current Hostinger naming, AWS/application re-pointing, no apps, multiple providers, and missing local kubeconfig context. Ensure automated use is deterministic and noninteractive.

## Acceptance

- [ ] Offline mocked tests with current `ubuntu-hostinger-` inventory select `APP_CONTEXT=ubuntu-hostinger` and the five correct Application names.
- [ ] Explicit incorrect prefix or context refuses with a meaningful target mismatch error, not a false cluster-health summary.
- [ ] Zero and multiple candidate application groups refuse safely, with informative diagnostics.
- [ ] A valid, unambiguous AWS-target inventory still resolves correctly; absent local kubeconfig context fails clearly.
- [ ] Actual missing pull secrets, OutOfSync apps, or unready pods on selected target still fail the smoke gate.
- [ ] Verify user-provided nine-failure scenario red before fix and green **or accurately failing real checks** after fix.
- [ ] Run shellcheck, existing smoke BATS and ordinary relevant regression suite; report counts and exact executed commands.
- [ ] Read-only live acceptance on M4/Hostinger confirms target selection and records real results before closing.

## Files

- `bin/smoke-test-cluster-health`
- `scripts/tests/bin/smoke_test_cluster_health.bats`
- `CHANGELOG.md`

No cluster changes, secrets creation, hub rebuild, ArgoCD reconfiguration, or test-gate bypass is authorized by this bug report.
