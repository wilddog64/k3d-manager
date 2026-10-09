# k3dm Tests failure-history investigation — 2026-10-07

## Attempt and actual evidence

Inspected the operator screenshot and the dashboard/exporter on v1.42.0.
The screenshot showed:

```text
Failed cases: 0
Failing test cases: No data
Latest run classification: passed
Suite freshness: 1.80 hours
Last successful run: 1.80 hours
```

## Cause and follow-up

The current failure table uses an instant query; no history table exists.
Current clearing is intentional. Add a separate range-based historical view without
reverting the Pushgateway PUT stale-series fix. Live Prometheus historical samples
were not queried; no runtime changes or new test runs were made.

See [bug and acceptance criteria](../bugs/2026-10-07-k3dm-tests-failure-history-missing.md).
Documentation link validation and repository pre-commit gates are run before publication;
BATS/ShellCheck runtime suites are not applicable to this documentation-only filing.
