# Bug: Bugs dashboard `Verified at` shows a bare date when the status was committed in the evening (Pacific)

**Filed:** 2026-10-18 (Claude, from an operator screenshot)
**Status:** VERIFIED — 2026-10-18: Claude fix; pytest 47/47, N1 red on pre-fix (other 2 reds are copy-location artifacts, same on a fixed copy); real row computes 2026-10-18 00:09Z; E2 live pending
**Priority:** P3 — cosmetic; the date is correct, only the time of day is missing
**Severity:** low
**Approval:** approved — operator, 2026-10-18: "go ahead" (file and fix by Claude)
**Release:** v1.43.4 (bug; exempt from the plan cap)
**Component:** `bin/k3dm-vectordb-metrics` (`_verification_commit`, `_with_commit_time`)

## Problem

On the k3dm Bugs dashboard, `docs/bugs/2026-10-17-hostinger-pod-ip-pool-exhausted-leaked-cni-reservations.md`
shows `Verified at` = `2026-10-17` while neighbouring rows show `2026-10-17 01:05Z`. Its status line
is `LIVE-VERIFIED — 2026-10-17: …` (a date without a time). The collector upgrades such a date to a
time only when the commit that first set `VERIFIED` has the same **UTC** date. That commit,
`13d88491`, was made at `2026-10-17T17:09:09-07:00` — `2026-10-18 00:09Z` — so the UTC date differs
and the time is dropped. Every status written after 17:00 Pacific loses its time this way.

The status date is written in the author's local date; the comparison must use the commit's
local date (its own `%cI` offset), and the displayed time stays UTC.

## Fix

`_verification_commit` also returns the commit's local calendar date (the first 10 characters of
`%cI`). `_with_commit_time` accepts the commit when either its UTC date or its local date equals the
status date. A status date that matches neither (an older date, as in
`test_verification_times_copy_status_date_for_direct_live_verification`) stays a bare date.

## Acceptance

```yaml
must:
  - id: M1
    text: A status date of 2026-10-17 whose first VERIFIED commit is 2026-10-17T17:09:09-07:00 yields Verified at "2026-10-18 00:09Z" (and the same for Live verified at).
  - id: M2
    text: A status date equal to the commit's UTC date still yields that commit's UTC time (existing behaviour).
must_not:
  - id: N1
    text: A status date that matches the commit's local date must not be left as a bare date (red on pre-fix, which returns "2026-10-17").
  - id: N2
    text: A status date matching neither the commit's local nor UTC date must not take the commit's time (2026-10-15 status, 2026-10-16 commit stays "2026-10-15").
evidence:
  - id: E1
    proves: [M1, M2, N1, N2]
    kind: offline
    text: pytest scripts/tests/bin/test_vectordb_bug_metrics.py; N1 shown red with METRICS_MODULE pointing at the pre-fix collector from git show.
  - id: E2
    proves: [M1]
    kind: live
    text: After the next Hermes index run (bin/k3dm-hermes runs the collector from this checkout; no deploy step), the Hostinger pod IP pool row reads Verified at 2026-10-18 00:09Z (operator screenshot).
interface:
  - bin/k3dm-vectordb-metrics _verification_times(root, ref, texts)
```
