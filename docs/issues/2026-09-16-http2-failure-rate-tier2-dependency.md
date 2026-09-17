# HTTP/2 failure-rate observability is deferred to Tier 2

## Current state

The E2E Grafana dashboard reports run-level failed-test counts, total-test counts, run success/failure, and failure trends by owning service and failure kind. It does not report an HTTP/2-specific failure rate.

The current E2E publication and Prometheus metrics do not carry an HTTP protocol/version label. Consequently, failures cannot be separated into HTTP/1.1 versus HTTP/2, and the dashboard must not imply that HTTP/2 coverage exists.

## Dependency

HTTP/2-specific failure-rate telemetry is deferred until Tier 2 E2E coverage is complete. Tier 2 must exercise the HTTP/2 path and publish the protocol/version (along with request or test outcome) as bounded metric labels before Grafana can calculate and display an HTTP/2 failure rate.

## Follow-up

When Tier 2 is complete:

1. Add a bounded protocol/version label to the E2E result schema and exporter metrics.
2. Add a Grafana failure-rate panel scoped to HTTP/2 and retain the existing run-level panels.
3. Add exporter, dashboard, and end-to-end observability tests proving the HTTP/2 series is present and correctly calculated.
