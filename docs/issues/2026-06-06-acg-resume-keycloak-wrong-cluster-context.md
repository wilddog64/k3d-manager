# Issue: acg-resume targets ubuntu-k3s for Keycloak — Keycloak lives on k3d-k3d-cluster

**Date:** 2026-06-06
**Component:** acg-resume / shopping-cart-identity / Keycloak
**Status:** Needs Fix

## Symptom

`acg-resume` (aws) job `c92f5e5e` failed with:

> Keycloak, deployed as part of the `shopping-cart-identity` ArgoCD application on the `ubuntu-k3s` cluster, failed to become fully ready and accessible to issue an admin token within the script's timeout period.

The script timed out waiting for Keycloak to be ready on the `ubuntu-k3s` cluster, then failed during realm import.

## Investigation

```
kubectl get pods -n shopping-cart --context ubuntu-k3s
# No resources found in shopping-cart namespace.

kubectl get applications -A --context ubuntu-k3s
# No resources found

kubectl get namespaces --context ubuntu-k3s
# No identity or shopping-cart namespace exists on ubuntu-k3s

kubectl get applications -A --context k3d-k3d-cluster | grep identity
# cicd  shopping-cart-identity  Synced  Healthy

kubectl get application shopping-cart-identity -n cicd --context k3d-k3d-cluster \
  -o jsonpath='{.spec.destination}'
# {"namespace":"identity","server":"https://kubernetes.default.svc"}

kubectl get pods -n identity --context k3d-k3d-cluster
# keycloak-dd754544c-bckgl  1/1  Running  0  3d1h
# ldap-56997b96d-t9pgf      1/1  Running  1  13d
# openldap-...              1/1  Running  1  13d
# postgres-keycloak-...     1/1  Running  0  3d1h
```

## Root Cause

The `shopping-cart-identity` ArgoCD application deploys Keycloak to `https://kubernetes.default.svc` — the **local k3d-k3d-cluster** — in the `identity` namespace. Keycloak is healthy there (3d uptime, 0 restarts).

The `acg-resume` script incorrectly targets the `ubuntu-k3s` cluster context when probing for Keycloak readiness and issuing the admin token. No `identity` namespace and no Keycloak pod exist on ubuntu-k3s.

## Fix Applied

None applied — this is a script configuration issue, not a transient pod failure. The `acg-resume` script must be updated to use the `k3d-k3d-cluster` context (not `ubuntu-k3s`) when performing Keycloak readiness checks and admin token retrieval.

## Notes

- Keycloak endpoint on k3d-k3d-cluster: `identity` namespace, deployment `keycloak`
- The ArgoCD `shopping-cart-identity` app destination server is `kubernetes.default.svc` (local cluster only)
- Related prior issues: `2026-05-12-keycloak-api-readiness-timeout-too-short.md`, `2026-05-13-keycloak-intermittent-startup-never-reaches-available.md`
- Fix should update the Keycloak context variable in the acg-resume / acg-up scripts to explicitly reference `k3d-k3d-cluster`
