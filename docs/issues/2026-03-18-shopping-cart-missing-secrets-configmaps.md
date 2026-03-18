# Issue: Shopping Cart Apps — Missing Secrets and ConfigMaps on Ubuntu k3s

**Date:** 2026-03-18
**Status:** OPEN — Gemini assigned to diagnose; Codex candidate for manifest fixes
**Priority:** HIGH — blocks all 5 services from reaching Running state

---

## Problem

After arm64 images were successfully pushed and the `ghcr-pull-secret` was created,
shopping cart pods on the Ubuntu k3s cluster continued to fail with two distinct errors:

1. **`CreateContainerConfigError`** — required Secrets and ConfigMaps do not exist on the app cluster
2. **`CrashLoopBackOff`** — pods that do pull images crash on startup (missing env vars / DB connection failures)

---

## Affected Pods (as of 2026-03-18 Gemini verification report)

| Service | Namespace | Failure Mode | Restart Count |
|---|---|---|---|
| `basket-service` | `shopping-cart-apps` | CrashLoopBackOff | 163 |
| `order-service` | `shopping-cart-apps` | 1/2 Running + Error | — |
| `product-catalog` | `shopping-cart-apps` | CrashLoopBackOff + CreateContainerConfigError | — |
| `payment-service` | `shopping-cart-payment` | ImagePullBackOff + CreateContainerConfigError | — |
| `frontend` | `shopping-cart-apps` | Unknown (ImagePull / pending) | — |

---

## Root Cause Analysis

### Sub-issue 1 — CreateContainerConfigError (missing k8s resources)

The following resources are referenced via `envFrom` or `env.valueFrom` in deployment manifests
but do **not exist** on the Ubuntu k3s cluster:

| Service | Resource Type | Name | Required? |
|---|---|---|---|
| `basket-service` | ConfigMap | `basket-service-config` | YES (`REDIS_HOST`, `REDIS_PORT`, `CART_TTL`, `OAUTH2_ENABLED`, `LOG_LEVEL`) |
| `basket-service` | Secret | `redis-cart-secret` | Optional (only if Redis auth enabled) |
| `order-service` | ConfigMap | `order-service-config` | YES (full `envFrom`) |
| `order-service` | Secret | `order-service-secrets` | YES (full `envFrom`) |
| `product-catalog` | ConfigMap | `product-catalog-config` | YES (full `envFrom`) |
| `product-catalog` | Secret | `product-catalog-secrets` | YES (full `envFrom`) |
| `payment-service` | Secret | `payment-db-credentials` | YES (`DB_URL`, `DB_USERNAME`, `DB_PASSWORD`) |
| `payment-service` | ConfigMap | `payment-service-config` | YES (full `envFrom`) |
| `payment-service` | Secret | `payment-encryption-secret` | YES (`ENCRYPTION_KEY`) |

These resources were never created on Ubuntu k3s. ESO (External Secrets Operator) is deployed on
the app cluster but is not configured with SecretStore paths for these services.

### Sub-issue 2 — CrashLoopBackOff (app-level crash after image pull)

`basket-service` (163 restarts) pulls the arm64 image successfully but crashes immediately.
Likely cause: `basket-service-config` ConfigMap is absent, so the app cannot read required
env vars (Redis host/port) and crashes on startup.

### Sub-issue 3 — payment-service ImagePullBackOff

`payment-service` is additionally blocked on image pull. ArgoCD sync status is `Unknown`
due to SSH tunnel resets during heavy gRPC calls. The updated arm64 tag may not have been
applied to the ArgoCD Application yet.

---

## ESO State

ESO is running on Ubuntu k3s but has **no SecretStore or ExternalSecret** objects configured
for `shopping-cart-apps`, `shopping-cart-payment`, or `shopping-cart-data` namespaces.
The Vault SecretStore on the infra cluster is namespace-scoped to `secrets` ns only.

---

## Fix Options

### Option A — Kustomize overlays in shopping-cart-infra (recommended)
Add `secrets-generator` or placeholder ConfigMap/Secret manifests in
`shopping-cart-infra/argocd/overlays/ubuntu-k3s/` per namespace.
Values can be dev-safe placeholders (Redis on `localhost:6379`, stub DB URL, stub encryption key).
ArgoCD will apply them automatically on next sync.

**Owner:** Codex (manifest authoring, no cluster dependency)
**Files:** `shopping-cart-infra/argocd/overlays/ubuntu-k3s/<namespace>/`

### Option B — ESO SecretStore + ExternalSecret for each service
Configure ESO on Ubuntu k3s to pull secrets from Vault.
Requires Vault to have the secret paths populated (currently unknown).

**Owner:** Gemini (live cluster work)
**Blocker:** Vault Kubernetes auth over tunnel is unreliable (known issue); static token fallback needed.

### Option C — Manual `kubectl create secret/configmap` (hotfix)
Gemini creates the resources manually with dev-safe values.
Does not persist across cluster rebuilds; short-term only.

**Owner:** Gemini

---

## Recommended Path

1. **Immediate (Gemini):** `kubectl describe pod` on each failing pod to confirm exact missing resource names.
2. **Short-term (Codex):** Add placeholder ConfigMap + stub Secret manifests to `shopping-cart-infra`
   as Kustomize overlays — ArgoCD deploys them automatically.
3. **Long-term:** Wire ESO SecretStore for each namespace once Vault paths are defined.

---

## Task Spec Location

When assigned: `docs/plans/v0.9.4-<agent>-shopping-cart-missing-secrets.md`

---

## Related Issues

- `docs/issues/2026-03-17-shopping-cart-ghcr-pull-secret-and-arch-mismatch.md`
- `docs/issues/2026-03-16-ubuntu-k3s-rebuild-instability.md`
- `docs/issues/2025-10-19-eso-secretstore-not-ready.md`
