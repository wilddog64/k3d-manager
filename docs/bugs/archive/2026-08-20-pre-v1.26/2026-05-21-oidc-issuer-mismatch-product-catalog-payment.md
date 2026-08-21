# Bug: OIDC issuer mismatch — ArgoCD SSO, Keycloak config, and payment service

**Date:** 2026-05-21 (updated 2026-05-22)
**Repos:** `shopping-cart-infra`, `shopping-cart-payment`
**Branch:** `k3d-manager-v1.4.9`

---

## Problem

Three locations configure their OIDC issuer as a stale local hostname, while the live
Keycloak advertises `https://keycloak.3ai-talk.org` in its discovery document (set via
`KC_HOSTNAME_URL` + `KC_HOSTNAME_STRICT=true`). The go-oidc (ArgoCD) and Spring Security
(payment) libraries validate that the issuer in the discovery doc exactly matches the
provider URL they were configured with. Mismatch → auth failure.

**Observed error (ArgoCD SSO):**
```
Failed to query provider "http://keycloak.shopping-cart.local/realms/shopping-cart":
oidc: issuer URL provided to client ("http://keycloak.shopping-cart.local/realms/shopping-cart")
did not match the issuer URL returned by provider ("https://keycloak.3ai-talk.org/realms/shopping-cart")
```

**Root cause per location:**
1. `shopping-cart-infra/identity/keycloak/kustomization.yaml` — `KC_HOSTNAME_URL=http://keycloak.shopping-cart.local` is the old local hostname; Keycloak itself is misconfigured and would advertise the wrong issuer until the live pod is restarted with the corrected ConfigMap.
2. `shopping-cart-infra/argocd/config/argocd-cm.yaml` — ArgoCD's OIDC `issuer` field still points to `http://keycloak.shopping-cart.local/realms/shopping-cart` (old local hostname).
3. `shopping-cart-payment/k8s/base/configmap.yaml` — payment service uses `http://keycloak.identity.svc.cluster.local/realms/shopping-cart` (internal svc DNS), which also does not match the external issuer.

Note: `shopping-cart-product-catalog` was already fixed (uses `https://keycloak.3ai-talk.org`).

---

## Fix

All three locations must use `https://keycloak.3ai-talk.org` as the issuer — matching
what Keycloak advertises in its discovery document. In-cluster HTTP traffic to Keycloak
still routes via `keycloak.identity.svc.cluster.local`; the issuer string is only for
discovery and JWT `iss` claim validation.

### Change 1 — `shopping-cart-infra/identity/keycloak/kustomization.yaml`

```yaml
# Before
  - KC_HOSTNAME_URL=http://keycloak.shopping-cart.local

# After
  - KC_HOSTNAME_URL=https://keycloak.3ai-talk.org
```

### Change 2 — `shopping-cart-infra/argocd/config/argocd-cm.yaml`

```yaml
# Before
    issuer: http://keycloak.shopping-cart.local/realms/shopping-cart

# After
    issuer: https://keycloak.3ai-talk.org/realms/shopping-cart
```

### Change 3 — `shopping-cart-payment/k8s/base/configmap.yaml`

```yaml
# Before
  oauth2.issuer-uri: "http://keycloak.identity.svc.cluster.local/realms/shopping-cart"
  oauth2.jwk-set-uri: "http://keycloak.identity.svc.cluster.local/realms/shopping-cart/protocol/openid-connect/certs"

# After
  oauth2.issuer-uri: "https://keycloak.3ai-talk.org/realms/shopping-cart"
  oauth2.jwk-set-uri: "https://keycloak.3ai-talk.org/realms/shopping-cart/protocol/openid-connect/certs"
```

---

## Files Changed

| Repo | Branch | File | Change |
|------|--------|------|--------|
| `shopping-cart-infra` | `shopping-cart-infra-v0.5.0` | `identity/keycloak/kustomization.yaml` | `KC_HOSTNAME_URL` → external URL |
| `shopping-cart-infra` | `shopping-cart-infra-v0.5.0` | `argocd/config/argocd-cm.yaml` | `issuer` → external URL |
| `shopping-cart-payment` | `docs/next-improvements` | `k8s/base/configmap.yaml` | `oauth2.issuer-uri` + `oauth2.jwk-set-uri` → external URL |

---

## Before You Start

1. Read `memory-bank/activeContext.md` and `memory-bank/progress.md` in the k3d-manager repo
2. In `shopping-cart-infra`: `git pull origin shopping-cart-infra-v0.5.0`
3. In `shopping-cart-payment`: `git pull origin docs/next-improvements`
4. Read both target files before editing:
   - `shopping-cart-infra/identity/keycloak/kustomization.yaml`
   - `shopping-cart-infra/argocd/config/argocd-cm.yaml`
   - `shopping-cart-payment/k8s/base/configmap.yaml`

**Branches (all work is on existing branches — do NOT create new ones):**
- `shopping-cart-infra`: `shopping-cart-infra-v0.5.0`
- `shopping-cart-payment`: `docs/next-improvements`

---

## Definition of Done

- [ ] `shopping-cart-infra/identity/keycloak/kustomization.yaml` uses `KC_HOSTNAME_URL=https://keycloak.3ai-talk.org`
- [ ] `shopping-cart-infra/argocd/config/argocd-cm.yaml` uses `issuer: https://keycloak.3ai-talk.org/realms/shopping-cart`
- [ ] `shopping-cart-payment/k8s/base/configmap.yaml` uses `https://keycloak.3ai-talk.org/realms/shopping-cart` for both `oauth2.issuer-uri` and `oauth2.jwk-set-uri`
- [ ] Commit in `shopping-cart-infra` with message: `fix(keycloak): update OIDC issuer URLs to external domain for ArgoCD and Keycloak config`
- [ ] Commit in `shopping-cart-payment` with message: `fix(auth): update OIDC issuer and JWK URIs to external Keycloak domain`
- [ ] Both commits pushed to their respective branches on origin
- [ ] Report back: one SHA per repo + confirm push succeeded

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the three listed targets
- Do NOT commit to `main` — work only on `shopping-cart-infra-v0.5.0` and `docs/next-improvements`
- Do NOT restart pods — that is a cluster operation handled separately

---

## Root Cause

All three locations were configured with stale local hostnames (`keycloak.shopping-cart.local`
or `keycloak.identity.svc.cluster.local`) set before `KC_HOSTNAME_URL` was changed to the
external domain. The OIDC issuer URL must always match what `KC_HOSTNAME_URL` advertises
in the discovery document — it is not the same as the network address used to reach Keycloak.
