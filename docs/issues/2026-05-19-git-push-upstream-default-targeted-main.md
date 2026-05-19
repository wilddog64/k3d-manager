# Git push upstream default targeted `main` instead of the feature branch

**Date:** 2026-05-19
**Repo:** `k3d-manager`

## What happened

While pushing the new `fix/keycloak-public-url` work from the shopping-cart repos, `git push origin fix/keycloak-public-url` updated the tracked upstream branch instead of creating/pushing the feature branch ref.

## Actual output

Relevant output from `git push origin fix/keycloak-public-url`:

```text
remote: Bypassed rule violations for refs/heads/main:
remote:
remote: - Changes must be made through a pull request.
remote: - Required status check "Go CI" is expected.
To github.com:wilddog64/shopping-cart-basket.git
   c718c1c..cb5a294  fix/keycloak-public-url -> main
```

```text
remote: Bypassed rule violations for refs/heads/main:
remote:
remote: - Changes must be made through a pull request.
remote: - 2 of 2 required status checks are expected.
To github.com:wilddog64/shopping-cart-order.git
   16640fd..fb578ca  fix/keycloak-public-url -> main
```

```text
remote: Bypassed rule violations for refs/heads/main:
remote:
remote: - Changes must be made through a pull request.
remote: - Required status check "CI" is expected.
To github.com:wilddog64/shopping-cart-frontend.git
   674116b..cb348c4  fix/keycloak-public-url -> main
```

Local branch config that explains the behavior:

```text
upstream
* fix/keycloak-public-url            cb5a294 [origin/main] fix(config): set Keycloak issuer URI to Cloudflare public domain
```

## Root cause

These worktrees are configured with `git config push.default=upstream`, and the new feature branch was created to track `origin/main` by rebasing. In that configuration, `git push origin <branch>` can push to the upstream branch name instead of the local branch name.

## Recommended follow-up

- Use an explicit refspec when creating feature branches, for example `git push origin HEAD:refs/heads/fix/keycloak-public-url`.
- Consider changing `push.default` to `simple` if the workspace should not target upstream branches by default.
- Be cautious with future multi-repo branch setup tasks, because the same shell command can land on `main` when branch tracking is inherited from `origin/main`.
