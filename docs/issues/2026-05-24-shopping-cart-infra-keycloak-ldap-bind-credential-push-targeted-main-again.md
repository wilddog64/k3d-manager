# Issue: shopping-cart-infra keycloak LDAP bind credential removal push targeted protected main again

**Date:** 2026-05-24
**Repo:** `shopping-cart-infra`
**Branch intended:** `fix/keycloak-ldap-bind-credential`

## What Was Attempted

Pushed the local commit for `identity/keycloak/keycloak-reconcile-hook-job.yaml` with:

```bash
git push origin fix/keycloak-ldap-bind-credential
```

## Actual Output

```text
To github.com:wilddog64/shopping-cart-infra.git
 ! [rejected]        fix/keycloak-ldap-bind-credential -> main (non-fast-forward)
error: failed to push some refs to 'github.com:wilddog64/shopping-cart-infra.git'
hint: Updates were rejected because a pushed branch tip is behind its remote counterpart. If you want to integrate the remote changes, use 'git pull' before pushing again.
```

## Root Cause

The local branch is still configured in a way that causes the generic push to map to the protected `main` branch instead of the intended feature branch.

## Follow-up

Will publish the same commit with an explicit refspec to `refs/heads/fix/keycloak-ldap-bind-credential`.
