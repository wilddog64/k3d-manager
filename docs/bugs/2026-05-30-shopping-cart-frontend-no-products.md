# Deferred Bug: shopping-cart-frontend shows "No products found" after make up

**Branch:** `k3d-manager-v1.5.0` (deferred to v1.7.0+)
**Severity:** P3 — UI loads but product catalog is empty; app functional otherwise
**Status:** DEFERRED — intentionally not fixed here; see rationale below

---

## Symptom

After `make up`, the shopping-cart-frontend renders correctly but the Products page
shows "No products found. Try a different search term." — no product data is displayed.

---

## Likely Root Cause

`product-catalog` service returns an empty product list. Candidates:
- `product-catalog` pod not yet healthy / still in CrashLoopBackOff at page load time
- `product-catalog` database connection uses stale ESO secret (same race as orders; ESO
  force-refresh may not have fully propagated before the app first queries)
- `product-catalog` Postgres schema not seeded with initial data

---

## Why Deferred

This bug is intentionally deferred to **v1.7.0 (Observability)** as a test case for the
Prometheus + Grafana monitoring stack. The goal:

1. v1.7.0 deploys Prometheus + Alertmanager on OCI
2. A PrometheusRule fires when `product-catalog` HTTP 5xx rate > threshold or pod restarts
3. The self-healing webhook (v1.8.0) auto-triggers ESO force-refresh + pod bounce
4. This smoke test validates the full detect → alert → heal loop end-to-end

Fixing it manually now would remove a real observable failure from the monitoring baseline.

---

## Fix (when ready — after v1.7.0 monitoring baseline)

1. Check `kubectl logs -n shopping-cart-apps product-catalog-<pod> --context ubuntu-k3s`
2. If DB auth failure: force-refresh `product-catalog-secrets` ExternalSecret + bounce pod
3. If empty data: seed Postgres `products` table from `shopping-cart-product-catalog` repo
4. If timing: add `product-catalog` to the ESO force-refresh loop in `shopping_cart.sh`

---

## Reference

- Screenshot captured: 2026-05-30
- ESO force-refresh fix already in `bbb4d008` (addresses orders; products may need same)
- Related: `docs/bugs/v1.5.0-bugfix-eso-stale-secrets-force-refresh.md`
