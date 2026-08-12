# Webhook token restored; concise status now reports downstream failures

**Date:** 2026-08-12
**Status:** Resolved for the status source; downstream authentication failures remain separate.

## Cause

The webhook LaunchAgent was listening on `127.0.0.1:7443`, but the local credential lookup used by
`make status` had no usable token. Restarting the LaunchAgent does not create credentials. Running
`bin/k3dm-webhook-setup` confirmed the existing Keychain token, refreshed the repository secret, and
reinstalled the LaunchAgent.

## Verification

```text
token_length=64
health_http=200
```

The concise status report then returned:

```text
  ✓ ArgoCD: HTTP 200
  ✓ Frontend: HTTP 200
  ✓ Keycloak: HTTP 200
  ✓ Prometheus: HTTP 200
  ✓ Grafana: HTTP 200
  ✓ Product images: 20/20 have image_url
  ! ESO ClusterSecretStore: not installed (no ClusterSecretStore on ubuntu-hostinger)
  ! ESO ExternalSecrets: not installed (no ExternalSecret CRD on ubuntu-hostinger)
  ! Data layer: not deployed (namespace shopping-cart-data absent on ubuntu-hostinger)
  ✗ Keycloak login: HTTP Error 401: Unauthorized
  ! Frontend login: skipped (no Keycloak token)
  ✗ ArgoCD login: HTTP 401
  ✗ Grafana login: HTTP 401
Overall: FAIL (3 errors, 4 warnings)
Details: make status-full
```

## Follow-up

The status source is healthy. Keycloak, ArgoCD, and Grafana credential/login failures are separate
service issues and require independent credential investigation.
