# lib-acg push routed to `main` by upstream config

## What I tried

Pushed the Phase 3 migration commit from `wilddog64/lib-acg` with:

```text
git -C /Users/cliang/src/gitrepo/personal/lib-acg push origin feat/phase3-migration
```

## Actual output

```text
To github.com:wilddog64/lib-acg.git
   b253b9b..f1c577c  feat/phase3-migration -> main
```

Remote ref verification showed:

```text
f1c577c6bec59e9541ceba06ae7be5c5f277a121	refs/heads/feat/phase3-migration
f1c577c6bec59e9541ceba06ae7be5c5f277a121	refs/heads/main
```

I then repaired `main` with a normal revert commit instead of a force push:

```text
To github.com:wilddog64/lib-acg.git
   f1c577c..c5d9068  HEAD -> main
```

## Root cause

`git config` in `wilddog64/lib-acg` had `push.default=upstream`, and `branch.feat/phase3-migration.merge=refs/heads/main`, so the unqualified push targeted `origin/main` instead of creating a separate remote `feat/phase3-migration` ref.

## Recommended follow-up

Update the branch tracking configuration so `feat/phase3-migration` pushes to a matching remote branch by default, or always use an explicit refspec when pushing feature branches from this repo.
