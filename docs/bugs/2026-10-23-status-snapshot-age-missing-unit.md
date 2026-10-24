# Bug: `make status` prints a stale hub snapshot's age without a unit

**Status:** OPEN
**Priority:** P3
**Severity:** low — cosmetic; the warning is right, but "344 old" reads as a bare number
**Release:** v1.43.5 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-23, by Claude, after the operator asked what "Hub snapshot: 20261009T170742Z (344 old)" meant
**Approval:** explicit 2026-10-23. The operator said: "go ahead to file a P3".

**Component:** `bin/cluster-status-summary` (hub snapshot line)

## Problem

`bin/cluster-status-summary` prints the hub snapshot's age in hours. The healthy line (age ≤ 168)
prints `(${_snapshot_age}h old)`. The warning line prints `(${_snapshot_age:-unknown} old)`, so a
14-day-old snapshot shows as `(344 old)`. It also doesn't say why it is a warning.

## Fix

### F1. Warning line

- With a parsed age: `Hub snapshot: <name> (<N>h old, over 7 days; run make snapshot)`.
- Without one (unparseable stamp): `Hub snapshot: <name> (age unknown)`.

The healthy line and the 168-hour threshold are unchanged.

## Tests

`scripts/tests/bin/cluster_status_summary.bats`, with `K3DM_SNAPSHOT_STAMP` pointing at a temp file:

1. A stamp 200 hours old prints `200h old, over 7 days; run make snapshot`.
2. An unparseable stamp prints `age unknown`.
3. A stamp 2 hours old still prints `(2h old)` with the green mark.

Show test 1 red against the pre-fix script.

## Files

- `bin/cluster-status-summary`
- `scripts/tests/bin/cluster_status_summary.bats`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: A hub snapshot older than 168 hours is shown with its age in hours, an "h" unit, the 7-day threshold and the make snapshot hint.
  - id: M2
    text: An unparseable snapshot stamp is shown as "age unknown".
must_not:
  - id: N1
    text: The healthy (≤168h) line, the threshold and the overall status verdict must not change.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, N1]
    text: bats scripts/tests/bin/cluster_status_summary.bats green; test 1 red on the pre-fix script.
  - id: E2
    kind: live
    proves: [M1]
    text: Operator's make status before the next make snapshot shows the new warning text.
interface:
  - bin/cluster-status-summary (env K3DM_SNAPSHOT_STAMP)
```

## Definition of Done

- [ ] F1 and a CHANGELOG `[Unreleased]` `### Fixed` entry; only the Files above change.
- [ ] `bats scripts/tests/bin/cluster_status_summary.bats` green; paste the summary.
- [ ] Test 1 shown red on a temp copy of the pre-fix script.
- [ ] Commit: `fix(status): show the stale hub snapshot age in hours`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT run `make snapshot` or reach the M2 store from tests.
- Do NOT modify files outside the Files list.
