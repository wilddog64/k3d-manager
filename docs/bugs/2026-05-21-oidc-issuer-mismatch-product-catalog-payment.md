# Bug: OIDC issuer mismatch in product-catalog and payment services

**Date:** 2026-05-21
**Repos:** `shopping-cart-product-catalog`, `shopping-cart-payment`
**Branch:** `k3d-manager-v1.4.9`

---

## Problem

`shopping-cart-product-catalog` and `shopping-cart-payment` configure their OIDC issuer
as `http://keycloak.identity.svc.cluster.local/realms/shopping-cart` (the internal
Kubernetes service DNS name). Keycloak is deployed with:

```
KC_HOSTNAME_URL=https://keycloak.3ai-talk.org
KC_HOSTNAME_STRICT=true
```

Keycloak's OIDC discovery document always returns `https://keycloak.3ai-talk.org/realms/shopping-cart`
as the issuer, regardless of which hostname the request arrived on. The go-oidc and
Spring Security libraries validate that the issuer in the discovery doc exactly matches
the provider URL the service was configured with. They don't match → token validation
fails with:

```
oidc: issuer URL provided to client ("http://keycloak.identity.svc.cluster.local/realms/shopping-cart")
did not match the issuer URL returned by provider ("https://keycloak.3ai-talk.org/realms/shopping-cart")
```

**Same class of bug as ArgoCD** (fixed in commit `5aa2d67f`) — ArgoCD used
`http://keycloak.shopping-cart.local`; these services use the internal svc DNS name.
Both cause the same go-oidc / Spring Security issuer validation failure.

---

## Fix

Update both services to use the external Keycloak URL as the issuer, matching what
Keycloak actually advertises. In-cluster traffic reaches Keycloak via its internal
service (`keycloak.identity.svc.cluster.local`) for the actual HTTP requests; the issuer
string is only used for discovery and JWT `iss` claim validation.

### Change 1 — `shopping-cart-product-catalog/k8s/base/configmap.yaml`

```yaml
# Before
  OAUTH2_ISSUER_URI: "http://keycloak.identity.svc.cluster.local/realms/shopping-cart"

# After
  OAUTH2_ISSUER_URI: "https://keycloak.3ai-talk.org/realms/shopping-cart"
```

### Change 2 — `shopping-cart-payment/k8s/base/configmap.yaml`

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

| Repo | File | Change |
|------|------|--------|
| `shopping-cart-product-catalog` | `k8s/base/configmap.yaml` | `OAUTH2_ISSUER_URI` → external URL |
| `shopping-cart-payment` | `k8s/base/configmap.yaml` | `oauth2.issuer-uri` + `oauth2.jwk-set-uri` → external URL |

---

## Definition of Done

- [ ] `shopping-cart-product-catalog/k8s/base/configmap.yaml` uses `https://keycloak.3ai-talk.org/realms/shopping-cart`
- [ ] `shopping-cart-payment/k8s/base/configmap.yaml` uses `https://keycloak.3ai-talk.org/realms/shopping-cart`
- [ ] Both configmaps committed and pushed in their respective repos
- [ ] Pods restarted in cluster to pick up the new ConfigMap values

## Root Cause

Services were configured with the internal Keycloak DNS name during initial setup, before
`KC_HOSTNAME_URL` was set to the external domain. The OIDC issuer URL must always match
what `KC_HOSTNAME_URL` advertises in the discovery document — it is not the same as the
network address used to reach Keycloak.
