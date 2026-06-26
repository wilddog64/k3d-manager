# Bug: Hostinger refresh/status drifts between app-cluster targets and stale local listeners

**Date:** 2026-06-25
**Provider:** `k3s-hostinger`
**Files:** `scripts/lib/providers/k3s-hostinger.sh`, `scripts/etc/argocd/projects/platform.yaml.tmpl`, `bin/k3dm-webhook`, `scripts/tests/lib/provider_contract.bats`

## What failed

Live `make status CLUSTER_PROVIDER=k3s-hostinger` reported:

```text
=== Service Health ===
  ✅ ArgoCD: HTTP 200
  ❌ Frontend: HTTP Error 502: Bad Gateway
  ✅ Keycloak: HTTP 200
  ✅ Prometheus: HTTP 200
  ❌ Grafana: HTTP Error 502: Bad Gateway
  ❌ Pushgateway: <urlopen error [Errno 61] Connection refused>
  ❌ Product images: HTTP Error 502: Bad Gateway
  ✅ ESO ClusterSecretStore: Ready=True
  ✅ ESO ExternalSecrets: 5/5 synced
  ❌ Data layer: 4 not ready: postgresql-orders, postgresql-payment
```

At the same time, Hostinger had no data-layer workloads at all:

```text
$ kubectl get pods -n shopping-cart-data --context ubuntu-hostinger -o wide
No resources found in shopping-cart-data namespace.
```

The shopping-cart apps and data-layer Applications on the hub ArgoCD were still targeting the old
ACG app-cluster:

```text
$ kubectl get application -n cicd data-layer --context k3d-k3d-cluster -o yaml
spec:
  destination:
    name: ubuntu-k3s
status:
  sync:
    status: Unknown
  conditions:
  - message: 'failed to get cluster info for "https://host.k3d.internal:6443": Get
      "https://host.k3d.internal:6443/version?timeout=32s": read tcp ... connection reset by peer'
```

Hostinger-only platform apps were also rejected by the `platform` project:

```text
InvalidSpecError: application destination server 'https://2.25.146.252:6443' and namespace 'monitoring'
do not match any of the allowed destinations in project 'platform'
```

The local Grafana listener was stale as well:

```text
$ launchctl list | grep grafana
-	1	com.k3d-manager.grafana-port-forward
```

and `~/.local/share/k3d-manager/logs/grafana-pf.log` still pointed at an old AWS endpoint.

## Root cause

There were three separate defects.

1. `scripts/lib/providers/k3s-hostinger.sh` registered `cluster-ubuntu-hostinger` directly with
   `k3d-manager/role=app-cluster`, but it never cleared that label from the previously active
   cluster secret. That left more than one ArgoCD cluster eligible for the `app-cluster`
   ApplicationSets, so `data-layer` and `shopping-cart-*` could stay pinned to `ubuntu-k3s`.

2. `scripts/etc/argocd/projects/platform.yaml.tmpl` only allowed the app-cluster destinations for
   `ubuntu-k3s`. Hostinger `secrets`, `cicd`, `monitoring`, and `trivy-system` apps were rejected
   with `InvalidSpecError`.

3. `_hostinger_refresh_access_layer()` only restarted the Grafana and Pushgateway LaunchAgents. It
   did not regenerate their plists for the current Hostinger context, so stale provider-specific
   listeners survived refresh. Also, Hostinger does not currently deploy `pushgateway`, but
   `bin/k3dm-webhook` treated it as a mandatory smoke check and reported a false failure.

## Required fix

1. On Hostinger cluster registration/refresh, ensure exactly one ArgoCD cluster secret keeps the
   `k3d-manager/role=app-cluster` label.
2. Allow Hostinger and the other supported app-cluster providers in the `platform` AppProject for
   `secrets`, `shopping-cart-apps`, `shopping-cart-payment`, `shopping-cart-data`, `cicd`,
   `monitoring`, and `trivy-system`.
3. Regenerate Hostinger Grafana and Pushgateway port-forward plists during refresh so they point to
   `ubuntu-hostinger`.
4. Skip the Pushgateway smoke check on providers that do not deploy it.

## Expected result after fix

- `data-layer` and `shopping-cart-*` Applications resolve to `ubuntu-hostinger`.
- Hostinger platform/observability apps no longer fail with `InvalidSpecError`.
- `make refresh CLUSTER_PROVIDER=k3s-hostinger` rebuilds the local Grafana listener from the
  current provider context.
- `make status CLUSTER_PROVIDER=k3s-hostinger` stops reporting Pushgateway as failed when the
  service is intentionally absent.
