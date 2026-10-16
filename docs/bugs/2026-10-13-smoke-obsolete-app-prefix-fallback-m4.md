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

## Fix specification (Claude, 2026-10-16)

**Approval:** explicit 2026-10-16 "please dispatch smoke-test prefix fix" (operator).

Work only in the worktree and branch you were launched in. Read `bin/smoke-test-cluster-health`
and `scripts/tests/bin/smoke_test_cluster_health.bats` in full first.

### 1. Target selection in `bin/smoke-test-cluster-health`

Replace everything from `ARGOCD_APP_PREFIX="${ARGOCD_APP_PREFIX-ubuntu-k3s-}"` through the
closing `fi` of the `if [[ -z "${APP_CONTEXT:-}" ]]` block (current lines 30–41) with logic that
follows these rules exactly. Keep `INFRA_CONTEXT` and `ARGOCD_NAMESPACE` defaults unchanged.

1. **One listing.** List Applications once:
   `_kubectl --no-exit --quiet -- --context="${INFRA_CONTEXT}" -n "${ARGOCD_NAMESPACE}" get applications -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.destination.name}{"\n"}{end}'`.
   Candidates are the lines whose name ends in `shopping-cart-basket`. A candidate's prefix is
   its name with the trailing `shopping-cart-basket` removed (it may be empty).
2. **No default prefix.** Delete the `ubuntu-k3s-` default.
   - `ARGOCD_APP_PREFIX` **set** (`${ARGOCD_APP_PREFIX+x}`, so an empty value counts as set):
     select the candidate whose name is exactly `${ARGOCD_APP_PREFIX}shopping-cart-basket`.
     Compare with `awk -F'\t' -v n=... '$1==n'`, never a regex built from the prefix. None
     → target error.
   - **unset:** exactly one candidate → use its prefix. Zero or more than one → target error.
3. **App context.** Let `dest` be the selected candidate's destination name.
   - `APP_CONTEXT` unset, `dest` empty (an in-cluster `destination.server` app) → `APP_CONTEXT="${INFRA_CONTEXT}"`.
   - `APP_CONTEXT` unset, `dest` is in `kubectl config get-contexts -o name` → `APP_CONTEXT="${dest}"`.
   - `APP_CONTEXT` unset, `dest` not a local context → target error naming `dest`, telling the
     operator to add that context or set `APP_CONTEXT`. **No fallback to `INFRA_CONTEXT`.**
   - `APP_CONTEXT` set, `dest` non-empty and different → target error (mismatch).
   - `APP_CONTEXT` set, `dest` empty or equal → honour `APP_CONTEXT`.
4. **Target error** = one helper, `_target_error`, that prints `[TARGET] <message>` to stderr,
   then the candidate list (one line each: `  <name> -> <dest, or (in-cluster) when empty>`, or
   `  (none)`), then `exit 2`. It runs before any `ghcr-pull-secret`, ArgoCD-sync or pod check,
   so a target error emits no `[FAIL]` lines and no `get secret` / `get pods` calls. Exit code
   1 stays "health checks failed"; 2 now means "could not pick a target".
5. Everything after target selection (the three secret checks, five sync checks, pod count and
   the summary) is unchanged.
6. Update the header comment: the `APP_CONTEXT` / `ARGOCD_APP_PREFIX` lines describe the rules
   above, and add `Exit: 0 healthy, 1 health check failed, 2 target could not be determined`.

### 2. Tests (`scripts/tests/bin/smoke_test_cluster_health.bats`)

Extend the kubectl stub with a `get applications` branch that prints `STUB_APPS` (tab-separated
`name<TAB>dest` lines; use `printf` with `\t` in tests), and a `STUB_MISSING_SECRET_NS` knob that
makes `get secret ... -n <that ns>` exit 1. Rewrite existing tests that encode the old defaults
(`ubuntu-k3s-` default, fallback for a non-local destination, explicit `APP_CONTEXT` winning
over a different destination). Required tests:

1. Current inventory: `STUB_APPS` holds the five `ubuntu-hostinger-shopping-cart-*` apps (dest
   `ubuntu-hostinger`) plus an unrelated `hub-grafana-dashboards`, contexts `k3d-k3d-cluster`
   and `ubuntu-hostinger`, no env set → exit 0, `9 passed`, secrets and pods read with
   `--context=ubuntu-hostinger`, sync checks read `ubuntu-hostinger-shopping-cart-basket`.
2. No candidates → exit 2, `[TARGET]` in output, no `[FAIL]`, no `get secret`/`get pods` in the call log.
3. Two candidates (`ubuntu-hostinger-` and `acg-aws-`), no prefix → exit 2, both names listed.
4. Same two, `ARGOCD_APP_PREFIX=acg-aws-`, context `acg-aws` present → exit 0 on `--context=acg-aws`.
5. `ARGOCD_APP_PREFIX=ubuntu-k3s-` with the hostinger inventory → exit 2, no `[FAIL]`.
6. Destination not a local context → exit 2, output names the destination.
7. `APP_CONTEXT=ubuntu-k3s` with destination `ubuntu-hostinger` → exit 2 (mismatch).
8. `APP_CONTEXT` equal to the destination → honoured, exit 0.
9. Empty destination → app checks on `INFRA_CONTEXT`, exit 0.
10. Empty prefix: `ARGOCD_APP_PREFIX=` with an app named exactly `shopping-cart-basket` → selected.
11. A real failure on the selected target still fails: hostinger inventory and
    `STUB_MISSING_SECRET_NS=shopping-cart-data` → exit 1, `[FAIL] ghcr-pull-secret MISSING in shopping-cart-data`.
12. `KUBECTL_STUB_MODE=fail` → non-zero exit and an explanatory message (adjust the existing test).

Show test 1 failing against the pre-fix script (a temp copy) — that is the reported nine-failure
scenario.

### 3. Docs

- `docs/howto/makefile.md`, the `make smoke` row or the paragraph under it: one sentence saying
  the cluster check finds the shopping-cart Applications in ArgoCD and exits 2 when the target
  is missing or ambiguous (`ARGOCD_APP_PREFIX` / `APP_CONTEXT` pick one).
- `CHANGELOG.md` `[Unreleased]`: one `Fixed:` entry.

### Files

`bin/smoke-test-cluster-health`, `scripts/tests/bin/smoke_test_cluster_health.bats`,
`docs/howto/makefile.md`, `CHANGELOG.md`. No other file.

### Mutations (Claude, at verification)

Each must turn a test red: accept the first of several candidates; fall back to `INFRA_CONTEXT`
for a non-local destination; drop the explicit `APP_CONTEXT` mismatch check; restore the
`ubuntu-k3s-` default.

### Definition of Done

- [ ] Items 1–3 exactly as written; `shellcheck bin/smoke-test-cluster-health` clean.
- [ ] `bats scripts/tests/bin/smoke_test_cluster_health.bats` green; paste the output.
- [ ] Leave the changes **uncommitted**. Claude verifies, commits and lands them with:
  `fix(smoke): find the shopping-cart target from ArgoCD and refuse an ambiguous one`

### What NOT to Do

- Do NOT contact a cluster; tests use the stub only.
- Do NOT create a PR, commit, switch branches, or use `--no-verify`.
- Do NOT modify files outside the Files list, including `memory-bank/`.
