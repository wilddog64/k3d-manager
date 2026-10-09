# Cloud test failure detail is missing from metrics and bounded logs

## Observed behavior

The cloud `make-test-all` job reported failing suites, but the Grafana table could show only a
suite-level count. The test metrics exporter published `k3dm_test_suite_cases` without the failed
case number, test name, or diagnostic reason. The cloud response also preserved only the first
failure context and final tail, so later failures were hidden when many cases failed.

## Fix scope

- Publish bounded `k3dm_test_failure` records with target, suite, case number, test name, and first
  diagnostic reason.
- Change the dashboard to show one current row per failed test case with human-readable columns.
- Include multiple failure summaries in the bounded cloud response while retaining the final tail,
  credential redaction, and the 2,000-character limit.

The exporter caps failure records and label lengths to avoid unbounded Prometheus cardinality. The
cloud response remains a bounded diagnostic excerpt, not a raw-log transport.
