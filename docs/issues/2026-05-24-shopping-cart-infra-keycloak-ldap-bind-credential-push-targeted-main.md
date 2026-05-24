# Issue: shopping-cart-infra keycloak LDAP bind credential push targeted protected main

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
remote: error: GH006: Protected branch update failed for refs/heads/main.
remote:
remote: - Changes must be made through a pull request.
To github.com:wilddog64/shopping-cart-infra.git
 ! [remote rejected] fix/keycloak-ldap-bind-credential -> main (protected branch hook declined)
error: failed to push some refs to 'github.com:wilddog64/shopping-cart-infra.git'
```

## Root Cause

The local branch was configured to track `origin/main`, so the generic push routed to the protected `main` branch instead of the intended feature branch.

## Follow-up

Pushed the same commit explicitly with:

```bash
git push origin HEAD:refs/heads/fix/keycloak-ldap-bind-credential
```

That created the feature branch on GitHub and published the approved change.
