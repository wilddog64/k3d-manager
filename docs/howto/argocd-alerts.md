# How-To: ArgoCD Alerts

This repo currently wires two ArgoCD alerts through Prometheus and Alertmanager:

- `ArgoCDAppDegraded`
- `ArgoCDAppOutOfSync`

Both alerts are scoped to the watched app set used by the dashboard and include
shopping-cart apps plus the supporting infrastructure services:

- `shopping-cart-apps`
- `shopping-cart-basket`
- `shopping-cart-frontend`
- `shopping-cart-identity`
- `shopping-cart-namespace`
- `shopping-cart-networking`
- `shopping-cart-order`
- `shopping-cart-payment`
- `shopping-cart-product-catalog`
- `shopping-cart-rules`
- `data-layer`
- `trivy-operator`
- `ubuntu-hostinger-eso`
- `ubuntu-hostinger-platform`

## Where To See Them

### Grafana

Open the hub Grafana dashboard:

- `https://grafana.3ai-talk.org`

Look for the dashboard titled **ArgoCD Apps & Image Updater Hub**. The relevant
panels are:

- `Watched App Health / Sync`
- `Watched App Sync Activity (5m increase)`
- `Possible Flapping (30m syncs)`

These panels show the same app set that the alerts watch.

### Alertmanager

Alertmanager receives the fired alerts in the `monitoring` namespace. The
preferred browser path is the Cloudflare hostname:

- `https://alertmanager.3ai-talk.org`

That hostname is backed by the local Alertmanager port-forward LaunchAgent.
If you need to debug the local listener directly, you can still port-forward the
service yourself and open `http://localhost:9093`.

### Cluster Objects

The alert rule and route are applied from the ArgoCD platform-ops manifests:

- `scripts/etc/argocd/platform-ops/prometheusrule.yaml`
- `scripts/etc/argocd/platform-ops/alertmanager-config.yaml`

You can confirm they exist with:

```bash
kubectl -n cicd get prometheusrule,alertmanagerconfig
```

## Where Alerts Send

The current Alertmanager route sends both alert names to the analyzer webhook:

- `https://webhook.3ai-talk.org/api/v1/analyze`

That webhook is served by the local `k3dm-webhook` process. If you need to
inspect delivery, check the webhook log:

```bash
tail -f ~/Library/Logs/k3dm-webhook.log
```

## How To Test

### 1. Validate the manifests and tests

Run the repo-level test that now checks the ArgoCD dashboard, Prometheus rule,
and Alertmanager route wiring:

```bash
bats scripts/tests/plugins/argocd_metrics_servicemonitor.bats
```

### 2. Confirm the alert path is reachable

Open `https://alertmanager.3ai-talk.org` and verify the Alertmanager UI loads.

### 3. Trigger a real alert in a disposable environment

The reliable live test is to create a temporary `Degraded` or `OutOfSync`
condition on a non-critical watched app in a disposable cluster, then wait for
the rule `for:` window to elapse:

- `ArgoCDAppDegraded` fires after 5 minutes
- `ArgoCDAppOutOfSync` fires after 15 minutes

After that, verify:

- the alert appears in Alertmanager
- `~/Library/Logs/k3dm-webhook.log` shows the analyzer request
- the Grafana panels show the same app in a churn or degraded state

If you only want to smoke-test the downstream handler, you can POST a mock
Alertmanager payload directly to the webhook analyzer endpoint. That validates
the delivery target, but not the Prometheus firing path.
