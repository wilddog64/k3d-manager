# k3dm Tests dashboard lacks a failure-history table

**Status:** FIXED (dashboard implementation; live Grafana verification pending)
**Filed:** 2026-10-07
**Affected release:** k3d-manager v1.42.0
**Type:** Observability / usability gap
**Source:** Operator Grafana screenshot and request

## Problem and evidence

At approximately 08:06 AM America/Los_Angeles on 2026-10-07, the operator selected
"Last 6 hours" in the k3dm Tests dashboard. The screenshot displayed:

```text
Failed cases: 0
Failing test cases: No data
Latest run classification: passed
Suite freshness: 1.80 hours
Last successful run: 1.80 hours
```

The Failed cases graph still showed earlier nonzero values, but no table exposed the
earlier failed tests, suites, or diagnostic reasons. A later passing run therefore leaves
an operator unable to inspect earlier failures from the dashboard's selected time range.

Earlier cloud run 9492a6f7 completed at 2026-10-07T12:41:01.969481Z with:

```text
body.status: failed
body.exit_code: 2
body.result_classification: failed_untriaged
[k3dm-test-metrics] 1384 cases, 7 failed
[k3dm-test-metrics] metrics pushed: test-all/local
```

[Retained cloud response](https://github.com/wilddog64/k3d-manager/blob/cloud-requests/responses/20261007T123414Z-make-test-all.final.json)
provides independent evidence of the earlier failed run; its bounded excerpt does not contain every failure.

## Reproduction

1. Publish a test-all run with failed cases and their diagnostic labels.
2. Confirm the current failure table shows the failed tests.
3. Publish a passing test-all run.
4. Select a dashboard time range covering both runs.
5. Observe that the graph shows prior failures but the current table says "No data",
   with no separate history table available.

## Confirmed cause and boundary

In scripts/etc/grafana/dashboards/k3dm-tests-configmap.yaml, the table queries
k3dm_test_failure with instant=true. Its description explicitly says "Empty on a clean run".
The dashboard has no separate failure-history panel.

The exporter now correctly uses Pushgateway PUT to replace the current grouping.
A passing run omits failed-case series and clears current failures. This is expected
latest-run behavior and must be preserved. This report is separate from the fixed
[stale failure series bug](2026-10-07-test-metrics-stale-failure-series.md).

Prometheus may retain previously scraped samples within its retention period.
Live historical sample availability was not queried. Scrape sample timestamps must not
be presented as exact run completion times, and repeated scrapes must not be counted
as separate failure occurrences.

## Expected behavior / acceptance

- Keep the existing latest-run failure table and its clean-run clearing behavior.
- Add a clearly named "Failures in selected time range" table that respects the dashboard range.
- Show target/origin, suite, case, test name, and bounded diagnostic reason; deduplicate
  repeated scrape samples and label any observed sample time accurately.
- Earlier failed cases remain discoverable after a passing run while retained history
  is available. Changing the range excludes failures outside that range.
- A clean latest run still reports zero current failures and passed.
- Empty history explains that no recorded failures exist in the selected range; distinguish
  unavailable data where feasible.
- Preserve bounded labels/redaction. Do not reintroduce stale current series, unbounded
  per-run metric labels, or unsupported exact-run attribution.
- Validate a failed -> passed sequence and time-range filtering with representative
  Prometheus data and live Grafana verification.

## Fix and validation

Added dashboard panel 8, `Failures in selected time range`, using
`max_over_time(k3dm_test_failure[$__range])`. This preserves the existing latest-run
table and current-series clearing behavior while exposing retained failure observations
from the selected Grafana range. Repeated scrapes are deduplicated by the range
aggregation. The table shows the Pushgateway `instance` as `Target / origin`, plus
suite, case, test name, bounded reason, and target; it does not claim an exact run time.

Validation:

```text
bats scripts/tests/plugins/grafana_dashboard_appsets.bats
1..38
ok 12 k3dm tests dashboard preserves failed cases across the selected range
...
ok 38 k3dm tests freshness stats aggregate to one latest value

pytest -q scripts/tests/bin/test_k3dm_test_metrics.py
24 passed in 0.61s
```

The focused dashboard contract and exporter tests pass. Live Grafana verification of a
failed-then-passed run and range filtering remains pending; historical visibility is
bounded by Prometheus retention and scrape availability.
