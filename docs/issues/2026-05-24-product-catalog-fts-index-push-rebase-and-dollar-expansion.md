# Product catalog FTS index push/rebase and commit-message `$$` expansion

**Date:** 2026-05-24
**Repo:** `shopping-cart-product-catalog`
**Branch:** `docs/next-improvements`

## What was attempted

Implemented the FTS-index PostSync cleanup and the ESO placeholder Secret cleanup from:
- `docs/bugs/2026-05-24-fts-index-job-dollar-quoting-busybox-ash.md`
- `docs/bugs/2026-05-24-secret-yaml-eso-argocd-conflict.md`

## Unexpected behavior

1. The first `git push origin docs/next-improvements` was rejected because the remote branch had advanced.

2. The initial commit message for the FTS-index fix shell-expanded `$$` when passed through the shell, so the recorded message was incorrect until amended.

## Actual output

Push rejection:
```text
To github.com:wilddog64/shopping-cart-product-catalog.git
 ! [rejected]        docs/next-improvements -> docs/next-improvements (non-fast-forward)
error: failed to push some refs to 'github.com:wilddog64/shopping-cart-product-catalog.git'
hint: Updates were rejected because the tip of your current branch is behind
hint: its remote counterpart. If you want to integrate the remote changes,
hint: use 'git pull' before pushing again.
hint: See the 'Note about fast-forwards' in 'git push --help' for details.
```

Shell-expanded commit message:
```text
[docs/next-improvements 2012a6c] fix(fts-index): remove CREATE FUNCTION from PostSync job — busybox ash strips 33426 in heredoc
 1 file changed, 15 deletions(-)
```

## Root cause

- The remote `docs/next-improvements` branch moved after the local base commit, so a fast-forward push was not possible.
- The shell expanded `$$` in an unescaped commit message string, replacing it with the shell PID.

## Recommended follow-up

- Rebase or pull the remote `docs/next-improvements` tip before pushing local commits.
- Use single quotes or escape `$$` when writing commit messages that must preserve literal dollar signs.
