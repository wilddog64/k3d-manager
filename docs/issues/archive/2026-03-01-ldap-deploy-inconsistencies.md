# Issue: `deploy_ldap` inconsistencies and task spec error

**Date:** 2026-03-01
**Component:** `scripts/plugins/ldap.sh`, `docs/plans/rebuild-infra-0.6.0-gemini-task.md`

## Description

1. `deploy_ldap` shows help when called with no arguments, despite the help message stating that `deploy_ldap` (with no args) is an example of "Deploy with defaults".
2. The `rebuild-infra-0.6.0-gemini-task.md` task spec instructs to run `deploy_ldap --enable-ldap`, but `--enable-ldap` is not a recognized option for the `deploy_ldap` function (it might have been confused with `deploy_ad --enable-ldap`).

## Reproducer

```bash
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_ldap
# Output: Usage: deploy_ldap ... (Help message)

CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_ldap --enable-ldap
# Output: ERROR: [ldap] unknown option: --enable-ldap
```

## Root Cause

1. In `scripts/plugins/ldap.sh`, the function `deploy_ldap` has an explicit check for `$arg_count -eq 0` to show help.
2. The task spec contains a typo/error in the command flag.

## Fix

1. Update `deploy_ldap` to proceed with defaults if no arguments are provided.
2. Use `deploy_ldap` without invalid flags in the rebuild process.
