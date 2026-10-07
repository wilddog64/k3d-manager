# Last-success metric investigation — 2026-10-07

The operator screenshot shows both elapsed ages at 3.41 hours. Equality after a passing
latest run is expected; refreshing an elapsed-age panel does not modify its stored timestamp.

Offline exporter reproduction at revision 8c345767644b42a2752a9f5d64c6076d90580d6a modeled PUT replacement:

```text
[k3dm-test-metrics] metrics pushed: test-all/local
passed: last_run=1000, last_success=1000
[k3dm-test-metrics] metrics pushed: test-all/local
failed: last_run=2000, last_success=ABSENT
[k3dm-test-metrics] metrics pushed: test-all/local
passed again: last_run=3000, last_success=3000
```

Root cause: failed payload omits last-success and PUT removes it. Follow up in
[bug acceptance criteria](../bugs/2026-10-07-test-metrics-last-success-lost-on-failure.md).
No live exporter, Pushgateway, or Prometheus was contacted. Documentation-only filing;
runtime BATS/ShellCheck are not applicable, and doc-link/pre-commit validation is required.
