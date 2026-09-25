# Bug: `bin/smoke-test-cluster-health` derives `ARGOCD_APP_PREFIX` and `APP_CONTEXT` from two independent hardcoded defaults

**Filed:** 2026-09-25
**Target branch:** `k3d-manager-v1.38.0` (held — v1.37.0 is awaiting merge)
**Files:** `bin/smoke-test-cluster-health`, `scripts/tests/bin/smoke_test_cluster_health.bats`, `CHANGELOG.md`
**Lineage:** third iteration of the same defect —
`docs/bugs/2026-09-13-smoke-test-cluster-health-stale-defaults-silent-exit.md` (DONE `77008edb`) →
`docs/bugs/2026-09-13-smoke-test-cluster-health-pods-checked-on-wrong-cluster.md` (FIXED) → this

---

## Problem

`make smoke` reported `0 passed, 2 failed` on 2026-09-25. Re-running the same script with one
variable corrected gave `9 passed, 0 failed`:

```
APP_CONTEXT=ubuntu-k3s bin/smoke-test-cluster-health   # 9 passed, 0 failed
bin/smoke-test-cluster-health                          # fails
```

No v1.37.0 code change caused this. The gate broke because a **cluster registration was renamed
out from under its two unrelated defaults.**

### What the gate does today

```bash
INFRA_CONTEXT="${INFRA_CONTEXT:-k3d-k3d-cluster}"
APP_CONTEXT="${APP_CONTEXT:-${INFRA_CONTEXT}}"
ARGOCD_APP_PREFIX="${ARGOCD_APP_PREFIX-ubuntu-k3s-}"
```

Section 2 reads Applications named `${ARGOCD_APP_PREFIX}shopping-cart-*` on `INFRA_CONTEXT`.
Sections 1 and 3 read pull secrets and pods on `APP_CONTEXT`. Those are two independent guesses at
*the same fact* — which cluster the checked apps deploy to.

### Why the premise expired

The 2026-09-13 fix set `APP_CONTEXT` to default to `INFRA_CONTEXT`, justified by "the hub is its own
app cluster." That was true then: the hub's app-cluster registration was named `ubuntu-k3s`.

Live on 2026-09-25 the hub has **three** app-cluster registrations in `cicd`:

| Secret | `name` | `server` | provider |
|---|---|---|---|
| `ubuntu-k3s-app-cluster` | `k3d-cluster` | `https://kubernetes.default.svc` | `k3d` (the hub itself) |
| `cluster-ubuntu-k3s` | `ubuntu-k3s` | `https://host.k3d.internal:6443` | `k3s-aws` |
| `cluster-ubuntu-hostinger` | `ubuntu-hostinger` | `https://2.25.146.252:6443` | `k3s-hostinger` |

The hub is still registered as an app cluster — but it is now called **`k3d-cluster`**. The name
`ubuntu-k3s` was re-pointed to the separate AWS cluster. So:

```
ubuntu-k3s-shopping-cart-basket   dest=ubuntu-k3s   Synced Healthy   -> runs on the AWS cluster
```

All six `ubuntu-k3s-shopping-cart-*` apps have `destination.name: ubuntu-k3s`, so their pods live on
the **remote k3s-aws cluster**, while `APP_CONTEXT` defaults to the hub. The gate checks apps on one
cluster and pods on another — precisely the defect the second doc closed, reintroduced without a
single line of code changing.

This is the third time a hardcoded context default has rotted. **The hardcoding is the bug**, not
the particular value.

## Fix — derive the context from the apps being checked

`ARGOCD_APP_PREFIX` already names the cluster. Resolve `APP_CONTEXT` from the Application's own
`destination.name` instead of defaulting it, so the two can never disagree.

### Before You Start

- `git pull origin k3d-manager-v1.38.0`; read `memory-bank/activeContext.md`.
- Read `bin/smoke-test-cluster-health` in full and `scripts/tests/bin/smoke_test_cluster_health.bats` in full.
- Note `_kubectl` needs `--no-exit` or `_run_command` exits the whole script (cause 1 of the first doc).

### S1 — resolve the app context from the first checked Application

After the existing `ARGOCD_APP_PREFIX` line, add a resolution step that runs only when
`APP_CONTEXT` was not set explicitly:

```bash
if [[ -z "${APP_CONTEXT:-}" ]]; then
  _resolved_dest="$(_kubectl --no-exit --quiet -- --context="${INFRA_CONTEXT}" \
    -n "${ARGOCD_NAMESPACE}" get application "${ARGOCD_APP_PREFIX}shopping-cart-basket" \
    -o jsonpath='{.spec.destination.name}' 2>/dev/null || true)"
  if [[ -n "${_resolved_dest}" ]] && kubectl config get-contexts -o name 2>/dev/null \
       | grep -qxF -- "${_resolved_dest}"; then
    APP_CONTEXT="${_resolved_dest}"
  else
    APP_CONTEXT="${INFRA_CONTEXT}"
  fi
fi
```

Keep `INFRA_CONTEXT` and `ARGOCD_APP_PREFIX` exactly as they are. An explicit `APP_CONTEXT` must
still win, so the assignment must be guarded by the `-z` test and the old
`APP_CONTEXT="${APP_CONTEXT:-${INFRA_CONTEXT}}"` line must be **removed**.

### S2 — report the resolution

Print one line before section 1 so a failure says which cluster was chosen and why:

```bash
echo "Infra context: ${INFRA_CONTEXT}; app context: ${APP_CONTEXT} (apps: ${ARGOCD_APP_PREFIX}shopping-cart-*)"
```

### S3 — header comment

Replace the `APP_CONTEXT` line with:

```bash
#   APP_CONTEXT        kubectl context for app cluster (default: resolved from
#                      ${ARGOCD_APP_PREFIX}shopping-cart-basket's destination.name,
#                      falling back to $INFRA_CONTEXT)
```

### Tests

Extend the existing stub-`kubectl` suite. The stub must answer
`get application ... -o jsonpath={.spec.destination.name}` from an env var, and a stub
`kubectl config get-contexts -o name` must list the fake contexts.

1. **Resolution:** destination `ubuntu-k3s`, contexts include `ubuntu-k3s`. Assert `get pods` and
   `get secret` calls carry `--context=ubuntu-k3s`, and `get application` carries
   `--context=k3d-k3d-cluster`.
2. **Fallback when the destination is not a local context:** destination `remote-only`, contexts do
   not list it. Assert pods are checked with `--context=k3d-k3d-cluster` and rc 0.
3. **Fallback when the destination is empty.** Assert `--context=k3d-k3d-cluster`.
4. **Explicit `APP_CONTEXT=remote-y` still wins** even though the destination says `ubuntu-k3s`.
5. Leave the existing healthy / kubectl-failure / empty-prefix tests passing unchanged.

Assert on tokens, never whole source lines. No bare `!`, no whole-line `grep -F`.

## Definition of Done

- [ ] S1–S3 applied; only the three listed files change
- [ ] `grep -c 'APP_CONTEXT:-${INFRA_CONTEXT}' bin/smoke-test-cluster-health` outputs `0`
- [ ] `grep -c '_kubectl --quiet --' bin/smoke-test-cluster-health` outputs `0`
- [ ] `shellcheck -x bin/smoke-test-cluster-health`: rc 0
- [ ] `bats scripts/tests/bin/smoke_test_cluster_health.bats` green — paste the summary
- [ ] CHANGELOG `[Unreleased]` → `### Fixed`: "`bin/smoke-test-cluster-health` resolves the app-cluster context from the checked ArgoCD Application's `destination.name` instead of a hardcoded default, so a cluster-registration rename can no longer make it check apps on one cluster and pods on another"
- [ ] Commit message verbatim: `fix(smoke): resolve cluster-health app context from the checked app's destination`
- [ ] Pushed; `git rev-parse origin/k3d-manager-v1.38.0` equals the commit SHA

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`
- Do NOT edit `scripts/lib/foundation/`, `scripts/lib/acg/`, `scripts/lib/system.sh`, or `Makefile`
- Do NOT replace `_kubectl` with bare `kubectl` for cluster reads (the `kubectl config get-contexts`
  call is local-only and is the one exception)
- Do NOT run anything against a live cluster
- Do NOT hardcode `ubuntu-k3s`, `k3d-cluster` or `ubuntu-hostinger` as a new default
