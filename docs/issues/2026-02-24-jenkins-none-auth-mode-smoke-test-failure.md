# Jenkins `none` Auth Mode Smoke Test Failure

**Date:** 2026-02-24
**Status:** Documented

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

## Fix Approach

In `scripts/plugins/jenkins.sh`, the `awk` script that strips LDAP config when no
directory service is enabled is incorrectly removing the entire `securityRealm` block.

The fix should ensure:
1. When no directory service is selected, a valid default `securityRealm` using
   `local` realm with explicit `chart-admin-username` / `chart-admin-password` is
   preserved — or the block is left intact with the Helm chart defaults.
2. `VAULT_PKI_LEAF_HOST` must be set before JCasC template processing so
   `unclassified.location.url` resolves correctly.

This is related to the existing known issue: `deploy_jenkins` (no vault) broken.
