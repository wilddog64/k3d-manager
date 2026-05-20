# Issue: `git push origin fix/acg-sandbox-ttl-check` targeted `main` because `push.default=upstream`

**Date:** 2026-05-19
**Repo:** `lib-acg`
**Branch:** `fix/acg-sandbox-ttl-check`

## What was tested

Attempted to push the feature branch after committing the sandbox TTL check work:

```text
git -C /Users/cliang/src/gitrepo/personal/lib-acg push origin fix/acg-sandbox-ttl-check
```

## Actual output

```text
remote: error: GH006: Protected branch update failed for refs/heads/main.
remote:
remote: - Changes must be made through a pull request.
To github.com:wilddog64/lib-acg.git
 ! [remote rejected] fix/acg-sandbox-ttl-check -> main (protected branch hook declined)
error: failed to push some refs to 'github.com:wilddog64/lib-acg.git'
```

## Root cause

`git config --get push.default` returns `upstream`, and the branch metadata still maps
`fix/acg-sandbox-ttl-check` to `refs/heads/main`:

```text
branch.fix/acg-sandbox-ttl-check.merge refs/heads/main
branch.fix/acg-sandbox-ttl-check.remote origin
```

That caused the unqualified push to target `main` instead of the feature branch.

## Recommended follow-up

Use an explicit refspec when pushing this branch:

```bash
git push origin HEAD:refs/heads/fix/acg-sandbox-ttl-check
```

If this branch is reused later, consider correcting the branch merge ref so `push.default=upstream`
does not keep resolving to `main`.
