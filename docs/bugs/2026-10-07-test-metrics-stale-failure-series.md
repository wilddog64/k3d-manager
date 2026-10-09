# Test metrics dashboard retains stale failed cases

**Status:** FIXED

## Evidence

After a `make test-all` run reported two failed cases and successfully pushed
`test-all/local`, the Grafana `Failing test cases` table still displayed older case labels
alongside the current result. The same run ended with:

```text
[k3dm-test-metrics] 2509 cases, 2 failed
[k3dm-test-metrics] metrics pushed: test-all/local
make: *** [test-all] Error 2
```

## Cause

`bin/k3dm-test-metrics` used Pushgateway `POST`. Pushgateway retained metric series from the
previous payload when a later run no longer contained those failed-case labels. The dashboard
queried `k3dm_test_failure` as the current table, so it mixed old and current failures.

## Fix and acceptance

The exporter now uses `PUT` for the target grouping, replacing the complete metric set on every
run. Its local HTTP regression test requires and accepts `PUT`. The dashboard table therefore
shows only the latest published failed-case labels for that target.

The same test-all run also exposed two issues in the focused Python suites: the metrics test
incorrectly rejected spaces in human-readable labels, and status reporting attempted to start a
new bot thread in an untrusted channel mismatch. The latter was corrected to retain the safe
response-URL fallback; existing incoming threads may still target their recorded channel.
