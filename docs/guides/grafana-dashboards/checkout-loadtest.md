# Checkout Load Test (`checkout-loadtest`)

[← Grafana dashboards index](../grafana-dashboards.md)

Seven panels over `k6_checkout_load_*` and `k6_vus`, templated on `$run_id`.

This dashboard is deployed to app clusters only; it is deliberately excluded from the hub.
The **shopping-cart-apps CPU saturation** panel fills there at all times because it uses
ordinary Kubernetes metrics. The six k6 panels fill only during and after a load test;
Hostinger retains 15 days of remote-write data. Until a run exists, `count(k6_checkout_load_requests_total_total) = 0`
and `No data` is expected for those panels (`docs/issues/2026-09-17-checkout-loadtest-dashboard-no-data.md`).
The scheduled baseline in [`v1.48.0-scheduled-baseline-loadtest.md`](../../plans/v1.48.0-scheduled-baseline-loadtest.md)
is the plan that keeps those panels filled.


---
