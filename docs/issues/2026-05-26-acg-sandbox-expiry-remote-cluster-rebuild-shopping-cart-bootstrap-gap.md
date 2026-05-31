# 2026-05-26 — ACG sandbox expiry left the rebuilt shopping-cart cluster half-bootstrapped

**Repository:** `k3d-manager`
**Context:** AWS ACG sandbox expired; `ubuntu-k3s` remote cluster had to be rebuilt

## What was tested

Checked the rebuilt remote cluster and the failing shopping-cart pods with:

```bash
kubectl --context ubuntu-k3s describe pod basket-service-856df56bd6-th7mh -n shopping-cart-apps
kubectl --context ubuntu-k3s describe pod frontend-568964db44-v2rpb -n shopping-cart-apps
kubectl --context ubuntu-k3s describe pod redis-cart-0 -n shopping-cart-data
kubectl --context ubuntu-k3s describe pod payment-service-789b779b45-x4wrf -n shopping-cart-payment
kubectl --context ubuntu-k3s logs -n shopping-cart-apps frontend-568964db44-v2rpb --previous
kubectl --context ubuntu-k3s get externalsecret -A
kubectl --context ubuntu-k3s get svc -A | rg "minio"
kubectl --context ubuntu-k3s get secret -A | rg "redis-cart-secret|payment-db-credentials|payment-encryption-secret|redis-orders-cache-secret|order-service-secrets|product-catalog-secrets"
```

## Actual output

`basket-service` is running but crash-looping because the Redis backend is unavailable:

```text
Name:             basket-service-856df56bd6-th7mh
Namespace:        shopping-cart-apps
Status:           Running
...
State:          Waiting
  Reason:       CrashLoopBackOff
...
Warning  BackOff  86s (x19 over 8m47s)  kubelet  Back-off restarting failed container basket-service in pod basket-service-856df56bd6-th7mh_shopping-cart-apps(07c830d1-52e4-46ec-b160-aa83190b5a12)
```

`basket-service` logs show the root cause:

```text
{"level":"fatal","timestamp":"2026-05-26T19:14:09.167Z","caller":"server/main.go:49","message":"failed to connect to Redis","error":"failed to connect to Redis: dial tcp: lookup redis-cart.shopping-cart-data.svc.cluster.local on 10.43.0.10:53: no such host","stacktrace":"main.main\n\t/app/cmd/server/main.go:49\nruntime.main\n\t/usr/local/go/src/runtime/proc.go:267"}
```

`frontend` is crashing because nginx cannot resolve the MinIO upstream:

```text
2026/05/26 19:16:09 [emerg] 1#1: host not found in upstream "minio.shopping-cart-data.svc.cluster.local" in /etc/nginx/conf.d/default.conf:64
nginx: [emerg] host not found in upstream "minio.shopping-cart-data.svc.cluster.local" in /etc/nginx/conf.d/default.conf:64
```

`redis-cart` cannot start because the secret it needs is missing:

```text
Name:             redis-cart-0
Namespace:        shopping-cart-data
Status:           Pending
...
Environment:
  REDIS_PASSWORD:  <set to the key 'password' in secret 'redis-cart-secret'>  Optional: false
...
Warning  Failed  3m18s (x26 over 8m30s)  kubelet  spec.containers{redis}: Error: secret "redis-cart-secret" not found
```

`payment-service` cannot start because its DB secret is missing:

```text
Name:             payment-service-789b779b45-x4wrf
Namespace:        shopping-cart-payment
Status:           Pending
...
Environment:
  DB_USERNAME:                 <set to the key 'username' in secret 'payment-db-credentials'>  Optional: false
  DB_PASSWORD:                 <set to the key 'password' in secret 'payment-db-credentials'>  Optional: false
  ENCRYPTION_KEY:              <set to the key 'encryption-key' in secret 'payment-encryption-secret'>  Optional: false
...
Warning  Failed  17s (x26 over 6m3s)  kubelet  spec.containers{payment-service}: Error: secret "payment-db-credentials" not found
```

The remote cluster only had a subset of the expected shopping-cart secrets:

```text
shopping-cart-apps      order-service-secrets                    Opaque                                4      6m25s
shopping-cart-apps      product-catalog-secrets                  Opaque                                4      9m8s
```

Argo CD showed `shopping-cart-payment` as synced, but the app was still progressing:

```text
NAME                            SYNC STATUS   HEALTH STATUS
shopping-cart-payment           Synced        Progressing
```

The live cluster had `redis-cart`, `payment-db-credentials`, `payment-encryption-secret`, and MinIO missing from the runtime state needed by the app layer:

```text
NAMESPACE            NAME                      STORETYPE            STORE           REFRESH INTERVAL   STATUS         READY
shopping-cart-apps   product-catalog-secrets   ClusterSecretStore   vault-backend   24h                SecretSynced   True
shopping-cart-data   postgres-orders-admin     ClusterSecretStore   vault-backend   24h0m0s            SecretSynced   True
shopping-cart-data   postgres-payment-admin    ClusterSecretStore   vault-backend   24h0m0s            SecretSynced   True
shopping-cart-data   postgres-products-admin   ClusterSecretStore   vault-backend   24h0m0s            SecretSynced   True
```

```text
$ kubectl --context ubuntu-k3s get svc -A | rg "minio"
# no output
```

## Root cause

The ACG AWS sandbox expired, so the remote cluster was rebuilt. The rebuild path did not fully restore the shopping-cart bootstrap prerequisites in the right order:

- `redis-cart-secret` was not present when `redis-cart` started.
- `payment-db-credentials` / `payment-encryption-secret` were not present when `payment-service` started.
- MinIO was not present in the rebuilt cluster, so `frontend` could not resolve `minio.shopping-cart-data.svc.cluster.local`.

This is a bootstrap-gating problem, not a single service bug. The remote cluster must be treated as ephemeral after ACG expiry, and the rebuild path must reapply and verify the infra dependencies before the app layer starts.

## Recommended prevention

- Keep the local `k3d` cluster intact; the recovery path here is the remote ACG/`ubuntu-k3s` rebuild only.
- Make the remote rebuild path idempotent and explicit: cluster, Vault, ESO, data-layer, then shopping-cart apps.
- Teach `make up` / `bin/acg-up` to always re-run Vault secret reconciliation after the sandbox expires, even if the local cluster already exists.
- Split that recovery step into two parts:
  - seed or re-validate the required Vault KV entries
  - wait for ESO to materialize the Kubernetes Secrets before app startup
- Add a post-rebuild smoke gate that fails fast if any of these are missing:
  - `redis-cart-secret`
  - `payment-db-credentials`
  - `payment-encryption-secret`
  - the `minio` service in `shopping-cart-data`
- Do not rely on manual secret seeding after an ACG expiry. The rebuild flow should recreate the full shopping-cart bootstrap state automatically.
- Treat a missing remote cluster as a normal recovery event, not a partial continue-from-last-state operation.

## Follow-up

- Update the `acg-up`/remote bootstrap flow to verify the Vault-backed secrets are present and then confirm `shopping-cart-data`, `shopping-cart-apps`, and `shopping-cart-payment` are all healthy before returning success.
- Add or expand a smoke test that checks for the secrets and services listed above after a fresh remote rebuild.
