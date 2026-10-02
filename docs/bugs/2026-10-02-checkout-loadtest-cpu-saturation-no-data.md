# Bug: Checkout Load Test "shopping-cart-apps CPU saturation" shows "No data"

**Filed:** 2026-10-02
**Status:** FIXED (pending sync)
**Branch:** `k3d-manager-v1.40.0`
**File:** `scripts/etc/grafana/dashboards/checkout-loadtest-configmap.yaml` (panel `id` 5)
**Tests:** `scripts/tests/plugins/grafana_dashboard_appsets.bats`
**Related:** `docs/bugs/2026-10-02-grafana-overview-firing-alerts-and-request-rate-no-data.md` (same defect class:
a fixed `[1m]` window over series that are not scraped often enough to put two samples in it)

## Symptom

On the Checkout Load Test dashboard, the CPU saturation panel shows "No data" even though
shopping-cart-apps is running on `ubuntu-hostinger`. The panel does not use `$run_id`, so unlike the
k6 panels it should never be empty.

## Evidence (hub Prometheus `monitoring/prometheus-kube-prometheus-stack-prometheus-0`, 2026-10-02)

| Query | Result |
|---|---|
| `sum(rate(container_cpu_usage_seconds_total{namespace="shopping-cart-apps"}[1m]))` | empty |
| `sum(rate(container_cpu_usage_seconds_total{namespace="shopping-cart-apps"}[5m]))` | `0.0061` |
| `sum(kube_pod_container_resource_limits{namespace="shopping-cart-apps",resource="cpu"})` | `1.7` |
| `max(count_over_time(container_cpu_usage_seconds_total{namespace="shopping-cart-apps"}[5m]))` | `5` (one sample per 60s) |

## Root cause

The series come from the `ubuntu-hostinger` kubelet at one sample every 60s. A `[1m]` range therefore
holds at most one sample, and `rate()` needs two, so the numerator is empty and so is the whole
expression.

`[$__rate_interval]` is **not** a fix here. The Prometheus datasource does not declare a scrape interval,
so Grafana assumes 15s and resolves `$__rate_interval` to about 60s on a one-hour view. That is the same
single-sample window. The window must cover several 60s scrapes, so it is fixed at `5m`.

## Fix

In `scripts/etc/grafana/dashboards/checkout-loadtest-configmap.yaml`, panel `id` 5, change only the
range in the `expr`.

Old:
```
"expr": "100 * (sum(rate(container_cpu_usage_seconds_total{namespace=\"shopping-cart-apps\"}[1m])) / clamp_min(sum(kube_pod_container_resource_limits{namespace=\"shopping-cart-apps\",resource=\"cpu\"}), 1))",
```
New:
```
"expr": "100 * (sum(rate(container_cpu_usage_seconds_total{namespace=\"shopping-cart-apps\"}[5m])) / clamp_min(sum(kube_pod_container_resource_limits{namespace=\"shopping-cart-apps\",resource=\"cpu\"}), 1))",
```

Add a `description` to the same panel, as a sibling of `"title"`:
```
"description": "CPU used by shopping-cart-apps as a percentage of its summed CPU limits. Uses a 5m rate window because the app-cluster kubelet is scraped once a minute; a 1m window holds a single sample and renders No data.",
```

Leave the k6 panels alone. They are empty only because no load test has published `k6_*` series yet,
which is expected.

## Test (append to `scripts/tests/plugins/grafana_dashboard_appsets.bats`)

```bash
@test "Checkout Load Test CPU saturation uses a window that spans several scrapes" {
  local file="${DASHBOARDS_DIR}/checkout-loadtest-configmap.yaml"
  local panel
  panel="$(yq -r '.data["checkout-loadtest.json"]' "$file" | jq -c '.panels[] | select(.id == 5)')"
  [ -n "$panel" ]
  jq -e '(.targets[0].expr | contains("container_cpu_usage_seconds_total")) and (.targets[0].expr | contains("[5m]")) and (.targets[0].expr | contains("[1m]") | not) and (.targets[0].expr | contains("$__rate_interval") | not) and (.description | contains("once a minute"))' <<<"$panel" >/dev/null
}
```

If the panels sit somewhere other than top-level `.panels` in this dashboard, adjust only the `jq`
path and say so in the report.

**Mutation check (must report):** put `[1m]` back in a copy under `BATS_TEST_TMPDIR`, point the test at
it, and confirm it goes red. Then remove the copy and run the whole file green.

## Rules

- `bats scripts/tests/plugins/grafana_dashboard_appsets.bats`: all green; paste the summary.
- `yq` parses the file, and the embedded JSON passes `jq -e .`.
- No cluster or network access.

## Definition of Done

- [ ] Fix applied exactly as written
- [ ] Test added and green; mutation result reported
- [ ] Status line set to `FIXED (pending sync)`
- [ ] Commit message: `fix(grafana): widen the Checkout Load Test CPU rate window past the scrape interval`
- [ ] Pushed to `origin/k3d-manager-v1.40.0`; report `git rev-parse origin/k3d-manager-v1.40.0`

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files other than the dashboard, the bats file above, and this doc
- Do NOT change the datasource or any other dashboard
- Do NOT commit to `main`
