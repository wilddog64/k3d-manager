# shopping-cart-infra fix/remove-redis-placeholder-secrets initially tried to push to protected main

**Date:** 2026-05-23
**Area:** `shopping-cart-infra` branch push

## What happened

While pushing `fix/remove-redis-placeholder-secrets`, the first `git push origin fix/remove-redis-placeholder-secrets` attempt was rejected because Git tried to update `main` instead of the feature branch:

```text
remote: error: GH006: Protected branch update failed for refs/heads/main.
remote:
remote: - Changes must be made through a pull request.
To github.com:wilddog64/shopping-cart-infra.git
! [remote rejected] fix/remove-redis-placeholder-secrets -> main (protected branch hook declined)
error: failed to push some refs to 'github.com:wilddog64/shopping-cart-infra.git'
```

## Root cause

The local branch inherited `origin/main` as its upstream, so the default push target resolved to the protected main branch.

## Follow-up

Use an explicit refspec when pushing this branch (`git push origin fix/remove-redis-placeholder-secrets:fix/remove-redis-placeholder-secrets`) or reset the upstream to the matching feature branch before future pushes.
