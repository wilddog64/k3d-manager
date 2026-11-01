# Bug: `codex-dispatch land` fast gate runs `scripts/ci/fast_gate.sh`, which a cross-repo task (lib-foundation) does not have

**Status:** OPEN
**Priority:** P3
**Severity:** low — a lib-foundation land always fails after its tests pass; workaround `K3DM_SKIP_FAST_GATE=1`
**Approval:** operator, 2026-11-01 ("go ahead to dispatch them according (parallel if possible)"; found while landing)
**Filed:** 2026-11-01
**Detected by:** Claude, landing `acg-hub-ec2-key-and-extend-profile` into lib-foundation `fix/acg-hub-ec2-key-and-extend-profile`
**Affected:** `bin/k3dm-codex-dispatch` (`_dispatch_land`, fast gate step ~line 833)
**Branch:** `k3d-manager-v1.43.13`

## Observed failure

On the M4, 2026-11-01, `land --slug acg-hub-ec2-key-and-extend-profile --allow-out-of-scope --test '...'` printed
`tests: passed`, then `env: 'scripts/ci/fast_gate.sh': No such file or directory`, recorded `land_refused`
(`reason: fast-gate`) and refused. Claude then fast-forwarded the lib-foundation fix branch by hand (`6706f64`), so the
ledger has no `land` or `verify` event for that task.

## Root cause

The fast gate step runs `scripts/ci/fast_gate.sh "origin/$target"` from the task worktree for every repo. Only
k3d-manager has that script.

## Fix

When the task worktree has no executable `scripts/ci/fast_gate.sh`, print
`land: fast gate not available in <repo>; --test is the gate` and continue, with no `land_refused`. Keep the current
behavior when the script exists, and keep `K3DM_SKIP_FAST_GATE=1`.

## Files

- `bin/k3dm-codex-dispatch`
- `scripts/tests/bin/k3dm_codex_dispatch.bats` (or the existing dispatcher land suite)
- `CHANGELOG.md`

## What NOT to do

- Do not skip the fast gate for k3d-manager tasks, and do not treat a fast gate script that exists but fails as absent.
- Do not run k3d-manager's fast gate against another repo's worktree.

## Acceptance

```yaml
must:
  M1: a land into a repo without scripts/ci/fast_gate.sh, whose --test passes, lands and writes a land event
  M2: a land into a repo whose scripts/ci/fast_gate.sh exits 1 is refused with land_refused reason fast-gate (paired control)
must_not:
  N1: a repo without the script never records land_refused reason fast-gate
  N2: a failing --test is still refused in a repo without the script
evidence:
  E1:
    proves: [M1, M2, N1, N2]
    kind: offline
    intent: You will see BATS with a scratch K3DM_WORKTREE_ROOT and two scratch git repos, one with a failing fast_gate.sh and one with none, show the land without a script succeed (red on the pre-fix dispatcher, which reports No such file or directory) and the land with a failing script refused.
    what: bats on the dispatcher land suite
interface:
  - bin/k3dm-codex-dispatch land --slug S --test CMD
  - ledger.jsonl under K3DM_WORKTREE_ROOT
```
