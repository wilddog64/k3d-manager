# E2E exporter emits empty-valued `e2e_last_run_duration_seconds`

**Date:** 2026-08-21
**Branch found on:** `k3d-manager-v1.26.0`
**Severity:** Minor / cosmetic — non-blocking
**Status:** OPEN (deferred out of v1.26.0)
**Origin:** Finding 1a of `docs/bugs/2026-08-21-lifecycle-e2e-live-acceptance-findings.md`

## Symptom

When an E2E run has a null `duration_seconds` (the Job crashed before emitting parseable
results), the `vulnerability-inventory-exporter` emits:

```
e2e_last_run_duration_seconds{run_id="…",tier="vcluster",service="…"}
```

— i.e. the metric line has **no value**, which is an invalid Prometheus exposition line.
The other four `e2e_*` series (`e2e_run_info`, `e2e_last_run_pass`,
`e2e_last_run_timestamp_seconds`, `e2e_last_success_timestamp_seconds`) are correct.

## Root cause

In `scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml` (embedded
`exporter.py`), the duration value is written straight from the parsed artifact without a
default when it is empty/null.

## Fix direction

Coerce an empty/null `duration_seconds` to `0` before emitting the metric line. Keep the
other four series unchanged. Add/extend the exporter unit coverage to assert a valid
`e2e_last_run_duration_seconds …  0` line is produced when the artifact carries no duration.

## Why deferred

Cosmetic — it does not affect the promotion-gate signal (`e2e_last_run_pass`) or the
dashboard/alert behaviour that item 1 relies on. Fold into a future release (v1.27.0 or a
follow-up observability pass).
