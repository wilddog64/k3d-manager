# Bug: deploy_argocd does not source LDAP vars before namespace dependency check

**Date:** 2026-04-24
**Branch:** `k3d-manager-v1.1.0`
**Status:** READY FOR IMPLEMENTATION

## Problem

`make up` reaches the fresh Hub bootstrap path and successfully deploys Vault and LDAP, but fails when Step 3.6 runs:

```bash
"${REPO_ROOT}/scripts/k3d-manager" deploy_argocd --confirm
```

Observed output:

```text
# home.org
dn: dc=home,dc=org
running under bash version 5.3.9(1)-release
INFO: [argocd] Verifying infrastructure foundations...
make: *** [up] Error 1
```

Cluster state at investigation time:

```text
NAME       STATUS   AGE
secrets    Active   4m25s
identity   Active   2m57s
```

There is no `ldap` namespace. LDAP is deployed to `identity`, as configured by:

```bash
export LDAP_NAMESPACE="${LDAP_NAMESPACE:-identity}"
```

## Root Cause

`scripts/plugins/argocd.sh` checks:

```bash
if ! _kubectl get ns "${LDAP_NAMESPACE:-ldap}" >/dev/null 2>&1; then
```

The previous fix replaced the hardcoded `ldap` namespace with `LDAP_NAMESPACE`, but `argocd.sh` does not source `scripts/etc/ldap/vars.sh`.

When `deploy_argocd` runs in its own dispatcher subprocess, `LDAP_NAMESPACE` is unset, so the expression falls back to `ldap` instead of the configured `identity` namespace.

The check is also using `_kubectl` without `--no-exit`. `_kubectl` delegates to `_run_command`, which exits the process on a nonzero command by default. That means a missing namespace aborts before the intended fallback branch can log and deploy the dependency.

## Required Fix

Update `scripts/plugins/argocd.sh` only.

1. Source LDAP vars near the other config loading blocks so `LDAP_NAMESPACE` is available to `deploy_argocd`.
2. Make the Vault and LDAP namespace dependency probes non-fatal by using `_kubectl --no-exit`.
3. Preserve existing behavior otherwise.

Expected dependency check behavior:

```bash
if ! _kubectl --no-exit get ns secrets >/dev/null 2>&1; then
   ...
fi
if ! _kubectl --no-exit get ns "${LDAP_NAMESPACE:-ldap}" >/dev/null 2>&1; then
   ...
fi
```

## Validation

Run:

```bash
shellcheck -x scripts/plugins/argocd.sh
bats scripts/tests/plugins/argocd.bats scripts/tests/plugins/argocd_deploy_keys.bats
./scripts/k3d-manager _agent_lint
./scripts/k3d-manager _agent_audit
```

If the existing `deploy_argocd --help` BATS failure or bootstrap shellcheck findings are still present, document them as pre-existing verification gaps rather than widening this fix.
