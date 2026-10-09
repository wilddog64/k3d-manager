# Test dashboard freshness stats use ambiguous raw vectors

**Status:** FIXED

## Evidence

Grafana displayed `Suite freshness` and `Last passing run` as large values with a tooltip
containing `instance="test-all-local", job="k3dm-tests"`. The panels queried the raw timestamp
gauges directly, so Prometheus returned one series per scraped Pushgateway grouping instead of a
single latest value.

## Cause

The dashboard used `time() - k3dm_test_last_timestamp_seconds` and
`time() - k3dm_test_last_success_timestamp_seconds` without aggregation or instant evaluation.
Additionally, the exporter wrote a last-success timestamp whenever parsed failures were zero,
even when Make returned a nonzero exit code.

## Fix

The panels now use `time() - max(...)` with instant queries and explicitly describe the units and
aggregation. The exporter only writes a last-success timestamp when both parsed failures and the
Make exit code are zero. Regression coverage verifies the nonzero-exit behavior and dashboard
aggregation contract.
