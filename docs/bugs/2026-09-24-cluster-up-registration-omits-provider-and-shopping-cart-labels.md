# `bin/cluster-up` registers the ACG app cluster with no provider and `shopping-cart: false`, so the data layer can never sync

**Filed:** 2026-09-24
**Status:** FIXED — `bin/cluster-up` + `scripts/tests/bin/cluster_up.bats`
**Branch:** `k3d-manager-v1.37.0`
**Third in the series:** `2026-09-23-hostinger-registration-never-sets-provider-label.md` and
`2026-09-24-hostinger-registration-resets-shopping-cart-label.md` — **same two labels, same
`register_app_cluster` contract, the other caller.**

## Symptom

A fully healthy sandbox cluster, and `make up` still fails at **Step 10b/14** after ~8 minutes
of waiting:

```
WARN: [acg-up] data-layer did not reach Synced within 300s — force-syncing and retrying (one attempt)...
INFO: [acg-up] data-layer not yet Synced after force-sync — waiting...      (x19)
ERROR: [acg-up] data-layer ArgoCD Application did not reach Synced after force-sync + 180s retry
WARN: [acg-up] failed (exit 1) — cleaning up local processes...
make: *** [up] Error 1
```

The wait could never succeed, because the Application does not exist and was never going to:

```
$ kubectl --context k3d-k3d-cluster -n cicd get application ubuntu-k3s-data-layer
Error from server (NotFound): applications.argoproj.io "ubuntu-k3s-data-layer" not found
```

`ubuntu-hostinger-data-layer` is `Synced`/`Healthy` in the same namespace. The difference is in
the cluster secrets:

```
NAME                       ROLE          SHOPPING-CART   PROVIDER
cluster-ubuntu-hostinger   app-cluster   true            k3s-hostinger
cluster-ubuntu-k3s         app-cluster   false           unknown
ubuntu-k3s-app-cluster     app-cluster   <none>          k3d
```

`data-git` (and `services-git`) select on **both** labels:

```yaml
clusters:
  selector:
    matchLabels:
      k3d-manager/role: app-cluster
      k3d-manager/shopping-cart: "true"
```

`shopping-cart: "false"` fails the selector, so no Application is generated for `ubuntu-k3s`,
so a wait loop polling for `ubuntu-k3s-data-layer` spins until its own timeout and kills the
provision — taking Steps 10c–14 with it, including the Keycloak + LDAP identity stack that
Tier 2 needs for real OIDC.

## Root cause

`register_app_cluster` defaults both labels when the caller does not pass them
(`scripts/plugins/argocd.sh:1481`, `:1495`, `:1520`):

```bash
local _shopping_cart="${ARGOCD_APP_CLUSTER_SHOPPING_CART:-false}"
...
_warn "[argocd] ARGOCD_APP_CLUSTER_PROVIDER unset — registering ... with provider 'unknown'"
```

`scripts/lib/providers/k3s-hostinger.sh:167-168` passes both. `bin/cluster-up:767` passed
**only the token**:

```bash
ARGOCD_APP_CLUSTER_TOKEN="${_argocd_sa_token}" \
  register_app_cluster
```

So the ACG path silently took `provider=unknown, shopping-cart=false` on every provision. The
two WARNs were printed, in the log, 40 lines before the failure — and describe the failure
exactly. Nothing read them.

## Fix

```bash
ARGOCD_APP_CLUSTER_TOKEN="${_argocd_sa_token}" \
  ARGOCD_APP_CLUSTER_PROVIDER="${ARGOCD_APP_CLUSTER_PROVIDER:-${_cluster_provider}}" \
  ARGOCD_APP_CLUSTER_SHOPPING_CART="${ARGOCD_APP_CLUSTER_SHOPPING_CART:-true}" \
  register_app_cluster
```

`_cluster_provider` is already normalized at `bin/cluster-up:64`
(`"${CLUSTER_PROVIDER:-k3s-aws}"`), so this stays correct for `k3s-gcp` and `k3s-az` too.
Both keep an explicit caller override.

## Test

`scripts/tests/bin/cluster_up.bats` — "acg-up registers the app cluster with a real provider and
the shopping-cart label" asserts both env assignments and that they precede
`register_app_cluster`. Mutation-proven against `git show HEAD:bin/cluster-up`.

## Still open — not touched here

1. **A duplicate cluster secret for the same cluster.** `cluster-ubuntu-k3s` (provider
   `unknown`) and `ubuntu-k3s-app-cluster` (provider `k3d`) both carry
   `argocd.argoproj.io/secret-type=cluster` and `role: app-cluster` for `ubuntu-k3s`.
   `_istio_ambient_target_provider` (`scripts/plugins/istio_ambient.sh:69-79`) returns the
   provider of the **first** secret whose `.data.name` matches — so ambient CNI dir selection
   for an AWS k3s cluster depends on secret iteration order, and `k3d` is a "specific" provider
   that would win with k3d-shaped paths. Deleting a cluster secret is load-bearing for ESO and
   for four AppSets, so this needs the operator's decision, not a cleanup guess.
2. **The error message loses the context**: `check: kubectl get application ubuntu-k3s-data-layer
   -n cicd --context ` — the variable is empty at that point, so the suggested command cannot be
   run as printed.
3. **The wait loop cannot distinguish "not yet Synced" from "will never exist."** ~8 minutes of
   identical `not yet Synced` lines for an Application that was never generated. Checking for
   the Application's existence first, and failing fast with the selector mismatch named, would
   have turned this into a one-line diagnosis.

## Lesson

Both label defects were found and fixed **per provider** (hostinger, twice, on Sep 23 and Sep 24)
rather than at the shared seam. `register_app_cluster` has two callers and defaults that are
wrong for both of them; fixing the caller that happened to be in front of you leaves the other
one broken and looking healthy. When a callee's default is wrong for every real caller, the
default is the bug — the audit should enumerate callers, not wait for each to fail in turn.
