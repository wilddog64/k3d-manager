# Bug: Hostinger refresh can leave frontend nginx pinned to stale shopping-cart service IPs

## Symptom

After a Hostinger refresh, cluster health can show:

- `shopping-cart-basket` briefly `OutOfSync / Healthy`
- `ubuntu-hostinger-platform` briefly `OutOfSync` or `Progressing`
- frontend root `https://frontend.3ai-talk.org/` returns `200`
- frontend API path `https://frontend.3ai-talk.org/api/products` times out, and the smoke check reports:

```text
❌ Product images: The read operation timed out
```

Frontend logs on `ubuntu-hostinger` show nginx timing out on the upstream:

```text
upstream timed out (110: Operation timed out) while connecting to upstream,
request: "GET /api/products HTTP/1.1",
upstream: "http://10.43.7.38:8082/api/products",
host: "frontend.3ai-talk.org"
```

At the same time, the live `product-catalog` Service may already have a different ClusterIP and healthy endpoints.

## Root Cause

Hostinger refresh already reapplies the hub `data-git`, `services-git`, and `platform-helm`
ApplicationSets and strips stale `ubuntu-hostinger-platform` tracking IDs from product-catalog
resources. During that reconcile, ArgoCD can recreate shopping-cart Services.

The frontend pod is long-lived nginx. It caches upstream DNS and can stay pinned to the old
ClusterIP after `product-catalog` or related app Services are recreated. That leaves:

- ArgoCD apps mostly healthy
- product-catalog pod healthy
- frontend `/` healthy
- frontend `/api/products` timing out on a dead/stale service IP

The same stale platform ownership pattern also showed up on `shopping-cart-basket`, so the
cleanup needs to cover both basket and product-catalog.

## Fix

In `scripts/lib/providers/k3s-hostinger.sh`:

1. Extend `_hostinger_clear_stale_platform_tracking_ids` to also clear stale
   `ubuntu-hostinger-platform:*` tracking IDs from the basket resource set.
2. Hard-refresh `shopping-cart-basket` in addition to `shopping-cart-product-catalog`
   and `ubuntu-hostinger-platform`.
3. When any stale app ownership is cleared, roll out `deployment/frontend` on
   `ubuntu-hostinger` and wait up to 120s so nginx re-resolves the in-cluster service DNS.

## Validation

- `bats scripts/tests/lib/provider_contract.bats`
- `shellcheck -S warning scripts/lib/providers/k3s-hostinger.sh`
- `./scripts/k3d-manager _agent_audit`
