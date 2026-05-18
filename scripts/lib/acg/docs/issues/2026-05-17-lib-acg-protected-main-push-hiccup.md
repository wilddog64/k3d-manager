# lib-acg: push initially targeted protected `main` before explicit feature ref

## What I tried
- Created `fix/acg-credentials-extend-dialog` from `origin/main`
- Committed the dialog fix and new test wrappers
- Attempted a first push with the branch's default upstream configuration

## Actual output

```text
remote: error: GH006: Protected branch update failed for refs/heads/main.
remote:
remote: - Changes must be made through a pull request.
To github.com:wilddog64/lib-acg.git
 ! [remote rejected] fix/acg-credentials-extend-dialog -> main (protected branch hook declined)
error: failed to push some refs to 'github.com:wilddog64/lib-acg.git'
```

## Root cause
- The local branch was still configured in a way that made the first push resolve to the protected `main` ref instead of the intended feature branch.

## Follow-up
- Pushed the commit explicitly with `git push origin HEAD:refs/heads/fix/acg-credentials-extend-dialog`
- The feature branch now exists on origin and is ready for PR creation
