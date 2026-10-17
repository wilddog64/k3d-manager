# Bug: the Bug Tracking table's "Open for" stops counting at the fix, not at live verification

**Status:** OPEN — spec ready, not dispatched
**Priority:** P3
**Approval:** approved — operator, 2026-10-17: "Open for to remind until we verify bug live instead of day we fix it"
**Found:** 2026-10-17, operator
**Affected:** `bin/k3dm-vectordb-metrics` (`_bug_status_metrics`), Bug Tracking dashboard table

## Symptom

A bug's **Open for** cell shows days since it was filed while its Status is open. Once Status says
FIXED it shows `—`, even when nobody has proven the fix on a live system. The column is the only
age reminder in the table, so a fixed-but-unproven bug stops nagging the moment code lands. That is
exactly the state that needs the reminder: the Verified and Live-verified columns exist because a
fix is not done until it is proven.

## Root cause

`_bug_status_metrics` sets the `k3dm_bug_info` sample value to `-2` for every `status == "fixed"`
row. The dashboard maps `-2` to `—`. Only rows that are not fixed get `days since filed`.

## Fix

In `_bug_status_metrics`, for a fixed row:

- release at least v1.43.2 (the verification columns apply) **and** not LIVE-VERIFIED: the value is
  days since filed, the same as an open bug, so **Open for** keeps counting;
- LIVE-VERIFIED: `-2` (unchanged — the reminder stops);
- release older than v1.43.2 (verification `n/a`): `-2` (unchanged — historic fixes were never
  tracked for verification and must not all light up).

A row with no filed date stays `-1` (`unknown`). Offline `VERIFIED` does not stop the count; only
live verification does. Update the table description in `docs/guides/grafana-dashboards.md` to say
when Open for stops. No dashboard JSON change: the column already renders day counts and both
mappings.

Tests in `scripts/tests/bin/test_vectordb_bug_metrics.py`.

## Acceptance

```yaml
must:
  - id: M1
    text: A FIXED bug doc assigned to release >= v1.43.2 whose Status is not LIVE-VERIFIED gets a k3dm_bug_info value equal to days between its filed date and now.
  - id: M2
    text: A FIXED bug doc with Status VERIFIED (offline, not live) on release >= v1.43.2 also keeps counting days since filed.
  - id: M3
    text: A bug doc whose Status is LIVE-VERIFIED gets value -2.
  - id: M4
    text: The open-bug value (days since filed) and the no-filed-date value (-1) are unchanged.
  - id: M5
    text: docs/guides/grafana-dashboards.md says Open for counts from filed until the bug is live-verified.
must_not:
  - id: N1
    text: A FIXED, not-live-verified bug on release >= v1.43.2 never gets -2 (red against the pre-fix code).
  - id: N2
    text: A FIXED bug on a release older than v1.43.2 never gets a day count (stays -2).
  - id: N3
    text: No test pushes to a real Pushgateway.
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2]
    kind: offline
    text: pytest cases in scripts/tests/bin/test_vectordb_bug_metrics.py calling _bug_status_metrics with a fixed `now`, synthetic doc texts and a tally; N1 shown red on the pre-fix file.
  - id: E2
    proves: [N3]
    kind: offline
    text: Tests call the metric builder only, never _push_bug_group / publish_bug_metrics.
  - id: E3
    proves: [M1, M3]
    kind: live
    text: Claude reads the Bug Tracking table after the next scan: a fixed-not-live v1.43.4 row shows a day count, a LIVE-VERIFIED row shows —.
interface:
  - bin/k3dm-vectordb-metrics _bug_status_metrics(root, ref=None, now=None, tally=None, texts=None, fixed_in=None, repo=..., verification_times=None) -> Prometheus text
  - k3dm_bug_info sample value (days | -1 unknown | -2 not counting)
  - bug doc header lines **Status:** (FIXED / VERIFIED — <date> / LIVE-VERIFIED — <date>) and **Filed:** YYYY-MM-DD (else the date prefix of the file name)
```
