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

## Refined Root Cause (after reading all manifests — 2026-03-18)

| Service | Issue | Status |
|---|---|---|
| `payment-service` | `payment-db-credentials` + `payment-encryption-secret` Secrets **do not exist** in `k8s/base/` — no `secret.yaml`, not in kustomization.yaml | TRUE missing files → Codex fix |
| `order-service` | `order-service-config` + `order-service-secrets` **exist** in `k8s/base/` and kustomization | ArgoCD sync Unknown → Gemini force sync |
| `product-catalog` | `product-catalog-config` + `product-catalog-secrets` **exist** in `k8s/base/` and kustomization | ArgoCD sync Unknown → Gemini force sync |
| `basket-service` | `basket-service-config` exists + included in kustomization; CrashLoopBackOff is app-level crash | Data layer (Redis, RabbitMQ) likely not deployed on Ubuntu k3s |

---

## Fix Plan

### 1. Payment — Codex (no cluster needed)
Add `k8s/base/secret.yaml` to `shopping-cart-payment` with dev-safe placeholder values:
- `payment-db-credentials` (keys: `username`, `password`)
- `payment-encryption-secret` (key: `encryption-key`)
Update kustomization.yaml to include `secret.yaml`.

**Spec:** `shopping-cart-infra/docs/plans/codex-payment-missing-secrets.md`
**Branch:** `fix/payment-missing-secrets`

### 2. Order + Product-catalog — Gemini (force ArgoCD sync)
Run `argocd app sync order-service` and `argocd app sync product-catalog` on infra cluster.
Resources already in git; sync Unknown because SSH tunnel resets gRPC during heavy sync.

### 3. Basket — Investigation
Data layer services (Redis in `shopping-cart-data` ns, RabbitMQ) may not be deployed on Ubuntu k3s.
`shopping-cart-infra/data-layer/` has the manifests but no ArgoCD Application deploys them.
Separate issue / future work.

---

## Long-term

Wire ESO SecretStore for each service namespace once Vault secret paths are defined.
Do not proceed until Vault Kubernetes auth over tunnel is stable (known issue).

---

## Related Issues

- `docs/issues/2026-03-17-shopping-cart-ghcr-pull-secret-and-arch-mismatch.md`
- `docs/issues/2026-03-16-ubuntu-k3s-rebuild-instability.md`
- `docs/issues/2025-10-19-eso-secretstore-not-ready.md`
