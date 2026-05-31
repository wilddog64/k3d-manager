# shopping-cart-frontend fix/product-display-cart-bugs initially tried to push to protected main

**Date:** 2026-05-23
**Area:** `shopping-cart-frontend` branch push

## What happened

While pushing `fix/product-display-cart-bugs`, the first `git push origin fix/product-display-cart-bugs` attempt was rejected because Git tried to update `main` instead of the feature branch:

```text
remote: error: GH006: Protected branch update failed for refs/heads/main.
remote:
remote: - Changes must be made through a pull request.
remote:
remote: - Required status check "CI" is expected.
To github.com:wilddog64/shopping-cart-frontend.git
! [remote rejected] fix/product-display-cart-bugs -> main (protected branch hook declined)
error: failed to push some refs to 'github.com:wilddog64/shopping-cart-frontend.git'
```

## Root cause

The local branch inherited `origin/main` as its upstream, so the default push target resolved to the protected main branch.

## Follow-up

Use an explicit refspec when pushing this branch (`git push origin fix/product-display-cart-bugs:fix/product-display-cart-bugs`) or reset the upstream to the matching feature branch before future pushes.
