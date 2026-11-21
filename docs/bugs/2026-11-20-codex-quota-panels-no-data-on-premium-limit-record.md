# Bug: Codex quota panels show "No data" when the newest rate-limit record is a `premium` one

**Status:** OPEN — captured 2026-11-20 from the operator's Agent activity dashboard screenshot, priority set by the operator
**Priority:** P2 (operator, 2026-11-20: "this should be a P2 because it originally had data but now disappears. I need to know claude and codex quota, especially codex as I didn't open its cli"); the quota panels go blank while the reading-age panel still counts, workaround: Codex `/status` or the session file
**Introduced by:** pre-existing (the exporter assumes one rate-limit record shape)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** investigation — since 2026-11-20 (Argon spec review, then dispatch to Flash when a WIP slot frees)
**Prior art:** exact-slug glob none; `make find-similar-docs` not run (unavailable on the M4 today, see the 2026-11-20 priv_open bug); grep for `rate_limits|k3dm_codex_quota` hit `docs/bugs/2026-11-07-claude-plan-quota-not-exported.md` and `docs/bugs/2026-11-14-quota-efficiency-panels-compare-only-last-two-readings.md` — titles read, different root cause (Claude quota export; panel comparison window)
**Approval:** operator, 2026-11-20: P2s are Claude's to finish, no grooming wait; dispatch to Flash. Target branch `k3d-manager-v1.45.0` (fix inside the open release, not a patch release).
**Intent approved:** operator, 2026-11-20

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

## Fix

1. **Parse filter** (`bin/k3dm-dispatch-metrics:703-706`, inside the session-file reader). Replace the
   `if isinstance(limits, dict):` test with a call to a new module-level helper, `_codex_quota_usable(limits)`,
   defined next to `_cost`. It returns True only when both hold:
   - `limits.get("limit_id")` is missing, `None`, or the string `"codex"`. Files written before `limit_id` existed
     have no such key, and the existing tests use that shape (`test_dispatch_metrics.py:2210`, `:3712`).
   - `limits.get("primary")` or `limits.get("secondary")` is a dict.

   When it returns False, `quota` keeps its earlier value for that file. Nothing else in the loop changes.
2. **No change at the two readers.** `_activity_metrics` (`:2147-2164`) and `newest_quota` (`:2941`) both read
   only `row["quota"]`, so the filter fixes both. Do not add a second filter there.
3. **Tests** in `scripts/tests/bin/test_dispatch_metrics.py`, per Test design below.
4. **CHANGELOG.md**: one line under `## [Unreleased]` → `### Fixed`.

## Contract readers

The contract is the `quota` field of the session-reader rows: a `(timestamp, rate_limits dict)` pair or `None`.
After the fix it only ever holds a Codex-limit record, never a `premium` one.

- **Writer:** `bin/k3dm-dispatch-metrics:703-706`. Changes (Fix item 1).
- **Readers:**
  - `bin/k3dm-dispatch-metrics:2147-2164` (`_activity_metrics`) writes `k3dm_codex_quota_sample_timestamp_seconds`,
    `k3dm_codex_quota_used_ratio` and `k3dm_codex_quota_resets_at_seconds`. Code unchanged; it now gets the
    `codex` record.
  - `bin/k3dm-dispatch-metrics:2941` (`newest_quota`) → `_quota_efficiency` (`:2234-2252`), which appends
    `secondary` to `codex-quota-observations.jsonl`. Code unchanged; it now gets the `codex` record.
  - Grafana `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml:416` (weekly), `:470` (5h),
    `:524` (reading age), `:1179` (efficiency coverage). The metric names and labels are unchanged. The age panel now
    shows the age of the last `codex` record, not of the last record of any kind.
  - Tests: `scripts/tests/bin/test_dispatch_metrics.py:2210-2218` and `:3702-3717` (records with no `limit_id`,
    must stay green unchanged), and `:2475-2499` (`_quota_efficiency` called directly, unaffected).
- **Runs where:** the M4 LaunchAgent `com.k3d-manager.dispatch-metrics` runs
  `bin/k3dm-codex-dispatch schedule-metrics` every 900 s from the working checkout. So a landed fix goes live at the
  next run on the M4. No hub promote is needed.

## Test design

- **Fixture lines, from a real capture.** Taken on m4-air on 2026-11-20 from
  `~/.codex/sessions/2026/11/20/rollout-*.jsonl` (codex-cli 0.166.0). Session ids and account fields are removed.
  Only the `rate_limits` dicts are copied. Each sits in an
  `{"type": "event_msg", "timestamp": ..., "payload": {"type": "token_count", "info": {...}, "rate_limits": ...}}`
  line:

      {"limit_id": "codex", "limit_name": null, "primary": {"used_percent": 82.0, "window_minutes": 300, "resets_at": 1795216973}, "secondary": {"used_percent": 100.0, "window_minutes": 10080, "resets_at": 1795534344}, "credits": {"has_credits": false, "unlimited": false, "balance": "0E-10"}, "individual_limit": null, "spend_control_reached": null, "plan_type": "plus", "rate_limit_reached_type": null}
      {"limit_id": "premium", "limit_name": null, "primary": null, "secondary": null, "credits": {"has_credits": false, "unlimited": false, "balance": "0E-10"}, "individual_limit": null, "spend_control_reached": null, "plan_type": "plus", "rate_limit_reached_type": null}

  Tests may set `resets_at` relative to `now`, as the existing tests do. The `limit_id`, null and nesting shape must
  stay as captured.
- **Harness:** `dispatch_metrics.render([], 0, now, prices={}, codex_home=home)` with a tmp `sessions/<day>/` tree,
  as at `:2197-2218`. Use `monkeypatch.setattr(dispatch_metrics, "_root", lambda: tmp_path / "state")` so
  `_quota_efficiency` writes its observation file under tmp, never the real `~/.local/share`.
- **Fixture assertion first:** each test asserts that its session file exists under `home / "sessions"`, and that
  `_root()` resolves under `tmp_path`.
- **Tags:** name the tests `test_bug_2026_11_20_E1_...` and `test_bug_2026_11_20_E2_...`.

## Acceptance

```yaml
must:
  - id: M1
    text: When a session file's last rate_limits record is a premium one with primary and secondary null, written after a codex record, the exporter emits k3dm_codex_quota_used_ratio for primary and secondary with the codex record's values, and k3dm_codex_quota_sample_timestamp_seconds equals the codex record's timestamp.
  - id: M2
    text: Across files, when the newest record overall is a premium-null one in file B and the newest codex record is in an older file A, the exported quota comes from file A's codex record.
  - id: M3
    text: A rate_limits record with no limit_id key (older files) and numeric limits is still exported exactly as before.
  - id: M4
    text: _quota_efficiency receives the codex record, so codex-quota-observations.jsonl gains the codex record's secondary used_percent and resets_at at the codex timestamp.
must_not:
  - id: N1
    text: A rate_limits record whose primary and secondary are both null becomes the exported quota sample (sets k3dm_codex_quota_sample_timestamp_seconds) when a usable codex record exists.
  - id: N2
    text: A record whose limit_id is present and not "codex" (for example "premium" with numeric limits) replaces the codex record's values in k3dm_codex_quota_used_ratio.
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    intent: The Codex weekly and 5h quota panels keep showing the real Codex numbers even when Codex writes its extra "premium" record last, which is what blanked them on 2026-11-20.
    check: pytest in scripts/tests/bin/test_dispatch_metrics.py per Test design. Case a - one file, codex then premium-null 10 s later; ratios 0.82 and 1.0 present and timestamp = codex stamp. Case b - file A codex older, file B premium-null newer; file A values exported. Case c (positive control) - codex record only; same values exported, which proves case a's assertion can pass. Case d - codex then premium with numeric limits (used_percent 5); the codex values are exported, the 0.05 value is not. Case e - no limit_id, numeric limits; exported as before. Pre-fix red - against bin/k3dm-dispatch-metrics at 10aafca6, cases a, b and d fail (record the command and output). Cases c and e pass on both.
  - id: E2
    proves: [M4]
    kind: offline
    intent: The quota-efficiency panel keeps getting fresh Codex readings instead of silently skipping them.
    check: pytest, the same fixture as case a, with _root monkeypatched to tmp; after render, tmp/state/codex-quota-observations.jsonl has a row whose timestamp is the codex record's and used_percent is 100.0. Pre-fix red at 10aafca6 - the file is absent or has no such row.
  - id: E3
    proves: [M3]
    kind: offline
    intent: Nothing else on the dispatch and activity dashboards changes.
    check: scripts/tests/bin/test_dispatch_metrics.py passes in full, with :2197-2218 and :3702-3717 unchanged; make lint (pinned ruff) clean on the touched files; git diff --check clean.
  - id: E4
    proves: [M1]
    kind: live
    intent: On your Agent activity dashboard, the Codex weekly and 5h quota panels show numbers again within 15 minutes of the fix landing, without waiting for the Codex reset.
    check: Claude on the M4 after land - bin/k3dm-dispatch-metrics --dry-run prints k3dm_codex_quota_used_ratio for primary and secondary; then, after the next LaunchAgent run, the operator's screenshot of both panels shows values and the reading age matches the newest codex record. Must be done while a premium record is still the newest one (before Codex is used again), or the check proves nothing; if Codex has been used since, say so and judge from E1.
interface:
  - session reader row field "quota" -> (timestamp, rate_limits dict) | None, Codex-limit records only (narrowed)
  - _codex_quota_usable(limits) -> bool (new, internal)
  - exported metric names and labels unchanged
```

## Files

- `bin/k3dm-dispatch-metrics` — `_codex_quota_usable` and the one-line change at `:703`.
- `scripts/tests/bin/test_dispatch_metrics.py` — new E1 and E2 tests.
- `CHANGELOG.md` — one line under `## [Unreleased]` → `### Fixed`.

## Worker definition of done

- The E1 and E2 tests exist and pass. Cases a, b and d, and E2, are shown red against `bin/k3dm-dispatch-metrics` at
  `10aafca6`. Record the command and the failing output in the commit message or the dispatch report.
- `scripts/tests/bin/test_dispatch_metrics.py` passes in full, and pinned ruff is clean.
