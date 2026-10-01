# Bug: k3dm-tests Exit code table exposes raw metric internals

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-10-01
**Status:** FIXED (`pending commit`)
**Severity:** low — the panel shows `Time`, `__name__`, `instance`, and `job` without making the
actual test result understandable.

## Evidence

The dashboard's Exit code panel queried `k3dm_test_exit_code` directly as a table. Grafana therefore
rendered the metric name and labels as columns, while the numeric result was difficult to identify
and interpret.

## Resolution

The panel now queries `last_over_time(k3dm_test_exit_code[7d])` as an instant table, removes the
metric-internal columns, renames the useful fields to `Runner`, `Job`, and `Result`, and maps the
known values to `PASS`, `EXPECTED ENVIRONMENT` (exit code 2), and `FAIL`.

Implementation commit is recorded after commit.
