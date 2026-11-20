# Bug: Codex quota panels show "No data" when the newest rate-limit record is a `premium` one

**Status:** OPEN — captured 2026-11-20 from the operator's Agent activity dashboard screenshot, priority set by the operator
**Priority:** P2 (operator, 2026-11-20: "this should be a P2 because it originally had data but now disappears. I need to know claude and codex quota, especially codex as I didn't open its cli"); the quota panels go blank while the reading-age panel still counts, workaround: Codex `/status` or the session file
**Introduced by:** pre-existing (the exporter assumes one rate-limit record shape)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** dispatch — since 2026-11-20
**Prior art:** exact-slug glob none; `make find-similar-docs` not run (unavailable on the M4 today, see the 2026-11-20 priv_open bug); grep for `rate_limits|k3dm_codex_quota` hit `docs/bugs/2026-11-07-claude-plan-quota-not-exported.md` and `docs/bugs/2026-11-14-quota-efficiency-panels-compare-only-last-two-readings.md` — titles read, different root cause (Claude quota export; panel comparison window)

## Symptom

On 2026-11-20 at about 15:35 PST, Grafana's Agent activity dashboard showed "Codex weekly quota used" and "Codex 5h
quota used" as **No data**, while "Quota reading age" showed 2.95 hours.

## Cause

Codex session files (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`, codex-cli 0.166.0) carry two kinds of
`rate_limits` record. Both are visible in the files from 2026-11-02 onward.

- `"limit_id": "codex"` has numeric `primary` and `secondary` limits.
  Newest one: 2026-11-20T20:37:38Z, primary 82% of 300 min, secondary 100% of 10080 min.
- `"limit_id": "premium"` has `"primary": null, "secondary": null`.
  Newest one: 2026-11-20T20:37:48Z, in two sessions started at 12:12.

`bin/k3dm-dispatch-metrics` keeps the last `rate_limits` dict in each file whatever its `limit_id` (`:703-706`).
`_activity_metrics` (`:2147-2163`) then picks the newest of those across all files.

That newest record was the `premium` one, 10 seconds newer than the last `codex` one. So the exporter writes
`k3dm_codex_quota_sample_timestamp_seconds`, which feeds the age panel, and skips `k3dm_codex_quota_used_ratio`,
because both limits are null.

The panels come back only when a newer `codex` record is written, which with the weekly limit at 100% will not
happen until the reset on 11-24.

The same `quota` field also feeds `:2941` (`newest_quota`); check that site too.

## Workaround

Read the limits in Codex with `/status`, or from the newest `"limit_id":"codex"` line in the session files.

## Fix direction (for triage)

- When parsing (`:703-706`), keep only records whose `limit_id` is `codex` or absent (older files), or whose
  primary or secondary limit is a dict. A record with both limits null should never replace a usable one.
- Apply the same rule at `:2941`.
- Add an offline test whose fixture session file ends with a `premium` record after a `codex` record, with the
  metric asserted present (red on the current code). Include a positive control with only a `codex` record.
- Build the fixture from a real record shape: copy the two lines above, with the session ids removed.
