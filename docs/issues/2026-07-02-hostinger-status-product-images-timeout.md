# Issue: Hostinger status still times out on `Product images` even when `ubuntu-hostinger-platform` is healthy

**Date:** 2026-07-02
**Provider:** `k3s-hostinger`
**Files:** `bin/cluster-status`, `bin/k3dm-webhook`

## What I Checked

I reran the live Hostinger status check:

```bash
make status CLUSTER_PROVIDER=k3s-hostinger
```

## Actual Output

The live run reported the platform app as healthy:

```text
=== ArgoCD Apps ===
...
cicd        ubuntu-hostinger-platform       Synced        Healthy
```

The same run still showed ArgoCD Image Updater churn:

```text
=== ArgoCD Image Updater ===
Deployment: 1/1 ready
Last cycle: applications=6 images_considered=3 images_skipped=3 images_updated=3 errors=0
WARN Flapping: 13 recent cycles wrote an update — an app may not be converging
Mode:
  Annotation-driven enrollment active for the applications below
Watching:
  shopping-cart-basket -> app=ghcr.io/wilddog64/shopping-cart-basket:latest
  shopping-cart-order -> app=ghcr.io/wilddog64/shopping-cart-order:latest
  shopping-cart-product-catalog -> app=ghcr.io/wilddog64/shopping-cart-product-catalog:latest
```

And the service health probe still timed out on product images:

```text
=== Service Health ===
  ✅ Alertmanager: HTTP 200
  ✅ ArgoCD: HTTP 200
  ✅ Frontend: HTTP 200
  ✅ Keycloak: HTTP 200
  ✅ Prometheus: HTTP 200
  ✅ Grafana: HTTP 200
  ❌ Product images: The read operation timed out
  ✅ ESO ClusterSecretStore: Ready=True
  ✅ ESO ExternalSecrets: 18/18 synced
  ✅ Data layer: 4/4 ready
```

## Root Cause

The timeout comes from the product-image probe path in `bin/k3dm-webhook`, which fetches `https://frontend.3ai-talk.org/api/products` with a fixed short timeout. The platform app itself is currently healthy; the remaining issue is probe latency, not ArgoCD sync drift.

The repeated flapping warning is separate: Image Updater is still continuously touching the three annotation-driven apps that remain on `:latest`.

## Follow-Up

- Inspect why `frontend.3ai-talk.org/api/products` is occasionally slower than the probe timeout.
- If the timeout is acceptable noise, widen the probe or retry once before failing.
- If the churn warning is the real concern, remove the `:latest` image-updater enrollment and switch to an immutable SHA/digest promotion path.

## Resolution

The Hostinger refresh path now always restarts `deployment/frontend` after the GitOps and Vault
reconciliation steps so nginx re-resolves the current `product-catalog` Service DNS even when no
stale ownership cleanup was needed.

Live validation after the change showed:

```text
✅ Frontend: HTTP 200
✅ Product images: 20/20 have image_url
```

The separate Image Updater flapping warning still remains because the three annotation-driven apps
continue to be managed from `:latest`; that is a distinct issue from the product-image timeout.
