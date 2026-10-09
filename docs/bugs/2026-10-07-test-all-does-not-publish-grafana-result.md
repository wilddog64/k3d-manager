# Direct test-all runs do not publish a Grafana result

**Filed:** 2026-10-07
**Release / branch:** v1.42.0 / `k3d-manager-v1.42.0`
**Status:** FIXED
**Severity:** Medium — a completed full-suite run can leave the test dashboard blank or stale
**Component:** `Makefile` test targets / `k3dm Tests` dashboard

## Observed behavior

The operator ran the full offline test target and Grafana showed no `k3dm_test_*` data. The
captured run ended with:

```text
Collected artifacts in scratch/test-logs/all/20261006-181511
[tripwire] blocked 245 call(s) to host tools; none reached a real binary:
make: *** [test] Error 1
```

`make test-all` composed `test`, `test-bin`, and `test-python`, but only the separate
`make test-metrics` wrapper captured the complete run and invoked `bin/k3dm-test-metrics`. A
direct or cloud-triggered `make test-all` therefore had no local publication path.

## Fix

`make test-all` now captures and streams its complete output, publishes one result through the
existing exporter on both pass and failure, and returns the original suite exit code. Metrics
publication remains best-effort and cannot turn a test failure into a pass. `make test-metrics`
remains a reporting target that always exits zero. The webhook lifecycle fallback skips its
second publication when the Make target already reported a successful push.

## Acceptance

- [x] Direct `make test-all` publishes `k3dm_test_last_timestamp_seconds` and the case/exit-code
      metrics even when a suite fails.
- [x] The original `make test-all` exit status is preserved.
- [x] Cloud jobs do not duplicate a successful Make-level publication.
- [x] Exporter or Pushgateway failure remains non-fatal to the test result.
- [ ] Operator runs a new `make test-all` and verifies the `k3dm Tests` dashboard has fresh data.
