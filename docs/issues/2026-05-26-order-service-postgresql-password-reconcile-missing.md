# Issue: `order-service` stays degraded after remote rebuild because `postgresql-orders` is never reconciled to the Vault password

**Date:** 2026-05-26
**Repository:** `k3d-manager`
**Status:** Open

## Symptoms

After the remote `ubuntu-k3s` cluster is rebuilt, `shopping-cart-order` remains `OutOfSync / Degraded` and the `order-service` pod keeps restarting.

The runtime failure is a PostgreSQL authentication error:

```text
org.postgresql.util.PSQLException: FATAL: password authentication failed for user "postgres"
```

The cluster data layer is otherwise healthy and the order app still consumes `order-service-secrets` from ESO, so this is not a missing-secret-object problem.

## Actual Output

From the live cluster:

```text
$ kubectl --context k3d-k3d-cluster -n cicd get application shopping-cart-order -o wide
NAME                  SYNC STATUS   HEALTH STATUS   REVISION                                   PROJECT
shopping-cart-order   OutOfSync     Degraded        a294dfc250cb1e6eecf1e07f478fa7c70c6b60d9   shopping-cart
```

```text
$ kubectl --context ubuntu-k3s -n shopping-cart-apps get pods -l app.kubernetes.io/name=order-service -o wide
NAME                             READY   STATUS             RESTARTS      AGE
order-service-5545485d98-rxf7g   0/1     Running            17 (9s ago)   59m
```

The previous container logs end with:

```text
FATAL: password authentication failed for user "postgres"
```

The current `acg-up` flow seeds Vault with `secret/data/postgres/orders` and syncs:

- `shopping-cart-data/postgres-orders-readwrite`
- `shopping-cart-apps/order-service-secrets`

But the bootstrap path only has a PostgreSQL password reconcile helper for `product-catalog`. There is no equivalent `order-service` reconcile step, so the remote rebuild can leave `postgresql-orders` running with a password that no longer matches the Vault/ESO value consumed by the app.

## Root Cause

`bin/acg-up` seeds and syncs the orders password, but it never explicitly re-applies that password to the live `postgresql-orders` instance before `order-service` starts.

That leaves two possible states after a rebuild:

- the app secret has the Vault password
- the PostgreSQL instance still accepts a different password

When that happens, Spring Boot fails during datasource initialization and the startup probe never succeeds.

## Recommended Follow-up

- Add an `order-service` reconcile step in `scripts/plugins/shopping_cart.sh`, mirroring `shopping_cart_reconcile_product_catalog`.
- Re-apply the Vault-backed password to `postgresql-orders` after `shopping_cart_seed_sandbox_vault_kv` / `shopping_cart_sync_vault_backed_secrets`.
- Force-refresh `order-service-secrets` and restart `order-service` if the running pod is still using a stale password.

## Verification

After the fix lands, verify:

```bash
kubectl --context k3d-k3d-cluster -n cicd get application shopping-cart-order -o wide
kubectl --context ubuntu-k3s -n shopping-cart-apps get pods -l app.kubernetes.io/name=order-service -o wide
kubectl --context ubuntu-k3s -n shopping-cart-apps logs deployment/order-service --tail=100
```

Expected outcome:

- `shopping-cart-order` returns to `Synced / Healthy`
- `order-service` reaches `Running`
- PostgreSQL authentication succeeds on startup
