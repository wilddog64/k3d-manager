# Bug: "Paused on daily quota until" shows a date that has already passed

**Filed:** 2026-10-09
**Branch:** `k3d-manager-v1.43.0`
**Status:** FIXED `be13c3fa` 2026-10-09 (Codex via worktree dispatch; Claude verified 67 pytest, both regression tests red with the fix removed, no Pushgateway series moved, landed with `land --test`). Live from the next Hermes tick.
**Priority:** P3 — display only; the pause itself expired and indexing runs
**Severity:** low
**Origin:** operator, 2026-10-09: the vectordb dashboard read `2026-10-05 00:05:00` next to a `success` result.

## Symptom

`k3dm_vectordb_index_paused_until_timestamp_seconds` is still the 2026-10-05 quota reset. The
panel maps only `0` to "not paused", so it shows the old date while the last result is `success`.

## Cause

`_refresh_index` in `bin/k3dm-hermes`:
- `metrics["paused_until"]` starts from `state["index_paused_until"]`;
- on success the function sets `state["index_paused_until"] = 0`, but the very next statement after
  the `if`/`elif` chain writes `state["index_paused_until"] = metrics["paused_until"]`, putting the
  old value back;
- the `noop` path returns early and publishes the same old value.

The guard `if paused_until and now < paused_until` is false for a past date, so nothing is blocked.

## Fix

In `_refresh_index`, after the `metrics` dict is built: if the stored `index_paused_until` is not in
the future (`<= now`), set `metrics["paused_until"] = 0` and `state["index_paused_until"] = 0`. A
future pause is unchanged. A new pause still comes from `_next_quota_reset(now)`.

## Files

| File | Change |
|---|---|
| `bin/k3dm-hermes` | the fix |
| `scripts/tests/hermes/test_hermes.py` | tests |

## Tests

With the index-docs and status subprocesses stubbed, and the pushed metrics captured:
1. State `index_paused_until` in the past, run succeeds: the pushed value is 0 and the state is 0.
2. The same with an unchanged fingerprint (`noop`): the pushed value is 0.
3. State `index_paused_until` in the future: result `paused`, and the pushed value is unchanged.

Mutation check: remove the fix. Tests 1 and 2 must fail.

## Rules

- Bare `pytest scripts/tests/hermes/test_hermes.py`: green.
- Do not commit. `.git` is read-only in the sandbox.
