# Bug: `DR_DRILL_KEEP=1` keeps the drill cluster but deletes its kubeconfig

**Filed:** 2026-10-10
**Branch:** `k3d-manager-v1.43.2`
**Status:** OPEN — spec ready (v1.43.2 batch 2; dispatch after v1.43.1 lands, since both edit `bin/dr-drill`)
**Priority:** P3 — debugging aid; the workaround is `k3d kubeconfig get dr-drill`
**Severity:** low

## Symptom

`DR_DRILL_KEEP=1` exists so the operator can look at the drill cluster after a failed run. The
teardown keeps the cluster and prints `kept cluster; delete with: k3d cluster delete dr-drill`. It
then deletes `~/.k3dm/dr-drill/kubeconfig` anyway, so `kubectl --kubeconfig` on the documented path
fails on the cluster that was kept for exactly that.

## Cause

In `_dr_drill_teardown` (`bin/dr-drill`), `rm -f -- "$DR_DRILL_KUBECONFIG"` sits after the KEEP
branch instead of inside the delete branch.

## Fix

- Delete the kubeconfig only when the cluster is deleted, or when it never started.
- When the cluster is kept, also print
  `[dr-drill] kubeconfig kept: <path>; use: kubectl --kubeconfig <path> --context k3d-dr-drill`.
- The staging-directory cleanup (`DR_DRILL_STAGE`) is unchanged: it holds decrypted export data and
  is always removed.

## Tests (`scripts/tests/bin/dr_drill.bats`, stubbed)

- With KEEP=1 after a started run: the kubeconfig file still exists, the message names its path, and
  the stage directory is gone.
- With KEEP unset: the kubeconfig is removed, and `k3d cluster delete dr-drill` was called.

Mutation: move the `rm` back outside the branch; the KEEP test goes red.

## Files

- `bin/dr-drill`
- `scripts/tests/bin/dr_drill.bats`
- `docs/howto/hub-dr-drill.md`: the KEEP paragraph names the kept kubeconfig
- `CHANGELOG.md`

Commit message: `fix(dr): DR_DRILL_KEEP keeps the drill kubeconfig with the cluster`
