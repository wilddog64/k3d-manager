# Fix-target contract had no regression coverage

## What was tested

- `make fix-list`
- `make -n fix-restart APP=x NS=y`
- `K3DM_FIX_MODE=1 bin/k3dm-ask-bash -lc 'make fix-list'`
- Documentation review of `docs/howto/slack-slash-commands.md`

## Actual output

The fix targets were live:

```text
$ make fix-list
  make fix-delete-pod                  APP and NS are required
  make fix-eso-refresh                 No arguments needed
  make fix-force-sync                  APP is required
  make fix-list                        List all fix targets with descriptions
  make fix-restart                     APP and NS are required
  make fix-status                      NS is required
  make fix-sync                        APP is required
```

```text
$ make -n fix-restart APP=x NS=y
test -n "x" || { echo "Usage: make fix-restart APP=<deployment> NS=<namespace>"; exit 1; }
test -n "y"  || { echo "Usage: make fix-restart APP=<deployment> NS=<namespace>"; exit 1; }
kubectl rollout restart 'deployment/x' -n 'y' --context 'ubuntu-k3s'
kubectl rollout status  'deployment/x' -n 'y' --context 'ubuntu-k3s' --timeout=120s
```

```text
$ K3DM_FIX_MODE=1 bin/k3dm-ask-bash -lc 'make fix-list'
  make fix-delete-pod                  APP and NS are required
  make fix-eso-refresh                 No arguments needed
  make fix-force-sync                  APP is required
  make fix-list                        List all fix targets with descriptions
  make fix-restart                     APP and NS are required
  make fix-status                      NS is required
  make fix-sync                        APP is required
```

## Root cause

The implementation existed in `Makefile`, `bin/k3dm-ask-bash`, and `bin/k3dm-webhook`, but there was no dedicated regression suite proving that:

- the `make fix-*` targets are still present,
- fix mode still allows `make fix-list` while denying unrelated `make` targets, and
- the docs still point to the real override variable.

That made the feature look unimplemented when operators checked the docs without a corresponding test-backed contract.

## Fix

- Added `scripts/tests/bin/fix_targets.bats` to pin the `make fix-*` surface and fix-mode sandbox behavior.
- Updated `docs/howto/slack-slash-commands.md` to document the real override variable: `FIX_CONTEXT`.

## Recommended follow-up

- Keep `scripts/tests/bin/fix_targets.bats` in the regular validation set whenever fix-mode docs or sandbox rules change.
