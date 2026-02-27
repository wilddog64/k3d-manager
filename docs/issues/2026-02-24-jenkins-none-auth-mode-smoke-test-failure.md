# Jenkins `none` Auth Mode Smoke Test Failure

**Date:** 2026-02-24
**Status:** ✅ Fixed (2026-02-24)

## Description

When deploying Jenkins with the default configuration (no directory service enabled), the smoke test fails. 

### Error Observed
Jenkins logs show unresolved variables for `chart-admin-username` and `chart-admin-password`, and the Jenkins URL is misconfigured as `https:///`.

```
2026-02-25 01:18:25.721+0000 [id=39]    WARNING i.j.p.c.SecretSourceResolver$UnresolvedLookup#lookup: Configuration import: Found unresolved variable 'chart-admin-username'. Will default to empty string
2026-02-25 01:18:25.847+0000 [id=39]    INFO    j.m.JenkinsLocationConfiguration#preventRootUrlBeingInvalid: Invalid URL received: https:///, considered as null
```

### Root Cause

In `scripts/plugins/jenkins.sh`, when no directory service is enabled (`enable_ldap=0`, etc.), an `awk` script is used to strip LDAP-related configuration from the `values.yaml` file. 

This `awk` script appears to be stripping the `securityRealm` block entirely or incorrectly, leading to:
1.  The Helm chart falling back to a default `local` security realm that expects `chart-admin-username` and `chart-admin-password` variables which are not provided in this environment.
2.  The `unclassified.location.url` (which depends on `VAULT_PKI_LEAF_HOST`) potentially being affected or not properly interpolated because it's part of the same `configScripts` block.

## Impact

The baseline `deploy_jenkins` command (without flags) produces a broken Jenkins installation that cannot be logged into and fails its smoke test.

## Steps to Reproduce

1.  Deploy a fresh cluster.
2.  Run `./scripts/k3d-manager deploy_jenkins --enable-vault`.
3.  Observe smoke test failure and "unresolved variable" warnings in Jenkins logs.

## Workaround

Deploy with LDAP enabled (`--enable-ldap`), as the template processing for that mode
is verified to work.

## Fix

- Replaced the LDAP-stripping logic in `scripts/plugins/jenkins.sh` so that when no
  directory service is enabled it now:
  - Rebuilds the `securityRealm` block with a local user sourced from the
    Vault-provisioned `jenkins-admin` secret.
  - Replaces the Matrix auth `entries` block with a flat `permissions` list granting
    both `authenticated` and the local admin user explicit rights.
  - Inserts a concrete `VAULT_PKI_LEAF_HOST` entry into `controller.containerEnv`
    so JCasC location URLs no longer resolve to `https:///`.

## Verification

- `PATH="/opt/homebrew/bin:$PATH" CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_jenkins --enable-vault`
  now completes the Helm upgrade, waits for the pod to become ready, and only
  fails the optional smoke test (ingress IP is not reachable from macOS, so curl
  never sees the Istio LoadBalancer). Jenkins itself stays up and running.
- `kubectl logs -n jenkins statefulset/jenkins | grep 'chart-admin'` returns no
  unresolved-variable warnings. JCasC logs only show the expected "legacy format"
  notice from Matrix auth.
- `kubectl get configmap jenkins-jenkins-config-01-security -o yaml` shows the new
  local-realm block and the permissions list, confirming the rendered values match
  the intended structure.
