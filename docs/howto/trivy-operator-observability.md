# How-To: Trivy Operator Observability

This repo now exposes Trivy Operator in three places:

- A Grafana Loki panel for `namespace="trivy-system"` controller=`job` reconcile errors
- A Prometheus alert for failed Trivy scan jobs
- A Trivy Operator `ServiceMonitor` so `/metrics` is scraped by `kube-prometheus-stack`

## Where To See It

### Grafana

Open Hub Grafana:

- `https://grafana.3ai-talk.org`

Look for the dashboard **ArgoCD Apps & Image Updater Hub**. The Trivy-specific panels are:

- `Trivy Scan Job Failures (30m)`
- `Trivy Operator Job Reconcile Errors`

The Loki panel is the fastest way to confirm the `SuccessCriteriaMet` / job-controller reconcile issue.

### Alertmanager

Open Alertmanager through Cloudflare:

- `https://alertmanager.3ai-talk.org`

Use the same basic-auth login that `make show-service-passwords` prints. The Trivy scan-job alert is named:

- `TrivyOperatorScanJobFailures`

That alert is routed to the analyzer webhook:

- `https://webhook.3ai-talk.org/api/v1/analyze`

## Metrics Path

Trivy Operator now ships a `ServiceMonitor` with the `release: kube-prometheus-stack` label. That means Prometheus scrapes the operator `/metrics` endpoint automatically and the dashboard can query Trivy findings/scan-job metrics directly.

## How To Test

Run the repo test that checks the version pin, dashboard panels, alert rule, Alertmanager route, and ServiceMonitor wiring:

```bash
bats scripts/tests/plugins/trivy_operator_observability.bats
```

For a live check, inspect the operator logs and Prometheus data:

```bash
kubectl -n trivy-system logs deploy/trivy-operator
kubectl -n monitoring port-forward svc/prometheus-operated 9090:9090
```

Then query the Trivy job-failure panel or search Loki for:

```logql
{namespace="trivy-system",pod=~"trivy-operator.*"} | json | controller="job" | msg="Reconciler error"
```
