# Bug: `make snapshot-list` shows only the first snapshot, because `ssh` in the loop reads the loop's input

**Status:** OPEN
**Priority:** P2 — the list hides every snapshot after the first, so a successful capture looks lost; workaround is listing the store directly. Retention also under-prunes (at most one removal per run), which is the safe direction.
**Severity:** medium
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Filed:** 2026-10-24, by Claude, after the operator's `make snapshot` finished
**Approval:** filed under the operator's 2026-10-24 rule proposal "fix all P0 to P2 bugs before we cut a release"; dispatch needs a go (it touches hub backup retention).
**Component:** `scripts/plugins/hub_snapshot.sh` (`_hub_snapshot_ssh`, `hub_snapshot_list`, `_hub_snapshot_prune_verified`), `scripts/tests/plugins/hub_snapshot.bats`
**Related:** `docs/plans/v1.43.8-hub-snapshot-weekly-schedule-and-age-retention.md` (changes the same retention code; land this first), `docs/bugs/2026-10-08-hub-snapshot-prune-deletes-newest-no-auto-retention.md`

## Symptom

2026-10-24 ~09:30 PDT, after `make snapshot` printed
`captured 20261024T152408Z to m2jump:k3dm-snapshots/20261024T152408Z`:

- `make snapshot-list` printed one line: `20261009T022625Z	3.4G	verified`.
- `ssh -n m2jump 'ls -1 k3dm-snapshots'` lists three: `20261009T022625Z`, `20261009T170742Z`,
  `20261024T152408Z`. No data is lost.

## Root cause

`_hub_snapshot_ssh` runs `ssh` without `-n`, so `ssh` reads standard input. Inside
`while read … done < <(_hub_snapshot_remote_names)`, every `ssh` call in the loop body inherits the
loop's input and drains the remaining names.

- `hub_snapshot_list` calls `ssh` (`du -sh`) for every name, so only the first name survives.
- `_hub_snapshot_prune_verified` calls `ssh` only when it removes a snapshot, so a run removes at
  most one, then the loop sees no more names.

No caller pipes data into `_hub_snapshot_ssh`, so `-n` is safe for all of them. The BATS `ssh` stub
never reads standard input, which is why the suite stayed green.

## Fix

- **F1.** `_hub_snapshot_ssh`: pass `-n` to `ssh`.
- **F2.** `scripts/tests/plugins/hub_snapshot.bats`: make the `ssh` stub drain standard input
  (`cat >/dev/null`) the way real `ssh` does, then add:
  1. `hub_snapshot_list` with three remote names prints three lines;
  2. `_hub_snapshot_prune_verified 1` with three verified names removes the two oldest.
- **F3.** `CHANGELOG.md` `[Unreleased]` `### Fixed` entry.

## Files

- `scripts/plugins/hub_snapshot.sh`
- `scripts/tests/plugins/hub_snapshot.bats`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: hub_snapshot_list prints one line per snapshot directory on the store, verified and incomplete.
  - id: M2
    text: Pruning to keep K removes every verified snapshot beyond the newest K in a single run.
must_not:
  - id: N1
    text: An ssh call inside a loop over remote names must not consume the remaining names (red on the pre-fix code with a stdin-draining ssh stub).
  - id: N2
    text: Pruning must never remove one of the newest K verified snapshots.
  - id: N3
    text: No test reaches the real snapshot host.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, N1, N2, N3]
    text: bats scripts/tests/plugins/hub_snapshot.bats green; tests for M1 and M2 red on the pre-fix hub_snapshot.sh with the draining stub.
  - id: E2
    kind: live
    proves: [M1]
    text: Claude runs make snapshot-list and it shows all three snapshots on m2jump (20261009T022625Z, 20261009T170742Z, 20261024T152408Z).
interface:
  - ./scripts/k3d-manager hub_snapshot_list
  - ./scripts/k3d-manager hub_snapshot_prune (K3DM_SNAPSHOT_KEEP)
  - ssh on PATH (stub), K3DM_SNAPSHOT_HOST, K3DM_SNAPSHOT_DIR
```

## Definition of Done

- [ ] F1–F3 on `k3d-manager-v1.43.5`; only the Files above change.
- [ ] M1 and M2 tests shown red on a temp copy of the pre-fix plugin.
- [ ] Commit: `fix(hub-snapshot): stop ssh from draining the remote-name loop`

## What NOT to Do

- Do NOT run `make snapshot`, `snapshot-prune` or any command against the real store.
- Do NOT change retention policy (count or age); that is the v1.43.8 plan.
- Do NOT create a PR, commit to `main`, or use `--no-verify`.
