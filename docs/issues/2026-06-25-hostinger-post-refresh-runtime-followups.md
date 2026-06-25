# Issue: Hostinger refresh/status wiring fixed, but runtime workloads still fail after ESO recovery

**Date:** 2026-06-25
**Provider:** `k3s-hostinger`
**Related bugfix:** `docs/bugs/2026-06-25-hostinger-refresh-status-app-cluster-drift.md`

## What was fixed first

- Hostinger is now the only active ArgoCD `app-cluster`
- Hostinger `platform` destinations are allowed
- Hostinger refresh now restores:
  - Grafana port-forward plist
  - reverse Vault tunnel
  - remote `vault-bridge`
  - `vault-token` + `ClusterSecretStore/vault-backend`
  - `ExternalSecret` force-sync
- `make status CLUSTER_PROVIDER=k3s-hostinger` now reports provider-correct ESO health instead of
  hub-cluster false positives

## Current live state after the fix

Final `make status CLUSTER_PROVIDER=k3s-hostinger` output:

```text
=== Service Health ===
  ✅ ArgoCD: HTTP 200
  ❌ Frontend: HTTP Error 502: Bad Gateway
  ✅ Keycloak: HTTP 200
  ✅ Prometheus: HTTP 200
  ❌ Grafana: HTTP Error 502: Bad Gateway
  ❌ Product images: HTTP Error 502: Bad Gateway
  ✅ ESO ClusterSecretStore: Ready=True
  ✅ ESO ExternalSecrets: 17/17 synced
  ❌ Data layer: 4 not ready: postgresql-orders, postgresql-payment
```

Related app state:

```text
=== ArgoCD Apps ===
cicd        acg-kube-prometheus-stack         OutOfSync   Degraded
cicd        data-layer                        OutOfSync   Healthy
cicd        shopping-cart-basket              Synced      Degraded
cicd        shopping-cart-frontend            Synced      Degraded
cicd        shopping-cart-order               Synced      Degraded
cicd        shopping-cart-payment             Synced      Degraded
cicd        shopping-cart-product-catalog     OutOfSync   Healthy
```

Relevant Hostinger pods after the fix:

```text
shopping-cart-apps      basket-service-...    0/1   CrashLoopBackOff
shopping-cart-apps      frontend-...          0/1   CrashLoopBackOff
shopping-cart-apps      order-service-...     0/1   Running / restarting
shopping-cart-payment   payment-service-...   0/1   CrashLoopBackOff
monitoring              grafana-...           0/3   Pending
monitoring              prometheus-...        0/2   Pending
```

## Findings

1. The infrastructure/bootstrap path is now correct: `vault-backend` is `Ready=True` and
   `ExternalSecrets` are `17/17 synced`.
2. The remaining failures are workload/runtime problems on the Hostinger cluster, not the earlier
   provider-routing/bootstrap drift.
3. `shopping-cart-data` still does not expose ready PostgreSQL/MinIO StatefulSets even though the
   ArgoCD `data-layer` app is now routed correctly and marked `Healthy`.
4. `frontend` still fails publicly because its upstream app stack remains degraded.
5. `acg-kube-prometheus-stack` still has pending Grafana/Prometheus workloads on Hostinger.

## Recommended follow-up

1. Inspect the Hostinger `shopping-cart-data` StatefulSets/PVCs/events to determine why ready
   replicas do not appear even after ESO converged.
2. Inspect `basket-service`, `order-service`, and `payment-service` current logs now that their
   secrets exist.
3. Inspect `monitoring` PVC / scheduling / resource events for the pending Grafana and Prometheus
   pods.
