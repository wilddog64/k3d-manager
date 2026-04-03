# Issue: ESO CRD API Version Mismatch (v1 vs v1beta1)

**Date:** 2026-03-31
**Branch:** `k3d-manager-v1.0.2`

## Problem
ArgoCD sync for `data-layer` fails on the remote `ubuntu-k3s` cluster because the manifests use `external-secrets.io/v1beta1`, while the installed External Secrets Operator (ESO) only serves `external-secrets.io/v1`.

## Analysis
- **Manifests:** Use `apiVersion: external-secrets.io/v1beta1`.
- **Cluster State:** ESO installed via Helm defaults to `v1`. The CRDs are present but `v1beta1` has `served: false`.
- **Error Message:** `The Kubernetes API could not find version "v1beta1" of external-secrets.io/ExternalSecret`.

## Root Cause
Divergence between the application repository manifests (shopping-cart-infra) and the default ESO installation version on the app cluster.

## Impact
Blocks the deployment of the data layer (PostgreSQL, RabbitMQ, Redis) which depends on ExternalSecrets for credential retrieval from Vault.

## Recommended Follow-up
1. Manually patch the `externalsecrets.external-secrets.io` and `secretstores.external-secrets.io` CRDs on `ubuntu-k3s` to set `served: true` for the `v1beta1` version.
2. Long-term: Upgrade application manifests to use the stable `v1` API.
