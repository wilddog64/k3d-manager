# Grafana Dashboards

This guide is the entry point for the Grafana dashboards shipped by this repository. The inventory below follows the 16 unique dashboard UIDs defined by the current labeled ConfigMaps and their deployment locations. Dashboard references document panels, metric producers, operational details, and known caveats.

## Dashboard inventory

| Dashboard | UID | Source file | Deployer | Cluster | Guide |
|---|---|---|---|---|---|
| ArgoCD Apps & Image Updater Hub | `argocd-image-updater-hub` | `platform-ops/grafana-dashboard-argocd.yaml` | `grafana-dashboards-hub` ApplicationSet; `make platform-ops` | hub | [Reference](grafana-dashboards/argocd-image-updater.md) |
| CVE Auto-Patch | `cve-autopatch` | `platform-ops/grafana-dashboard-cve-autopatch.yaml` | `grafana-dashboards-hub` ApplicationSet; `make platform-ops` | hub | [Reference](grafana-dashboards/cve-autopatch.md) |
| E2E Verification | `e2e-verification` | `platform-ops/grafana-dashboard-e2e.yaml` | `grafana-dashboards-hub` ApplicationSet; `make platform-ops` | hub | [Reference](grafana-dashboards/e2e-verification.md) |
| Hermes Status | `hermes-status` | `platform-ops/grafana-dashboard-hermes.yaml` | `grafana-dashboards-hub` ApplicationSet; `make platform-ops` | hub | [Reference](grafana-dashboards/hermes-status.md) |
| k3dm Host Disk | `k3dm-host-disk` | `platform-ops/grafana-dashboard-host-disk.yaml` | `grafana-dashboards-hub` ApplicationSet | hub | [Reference](grafana-dashboards/k3dm-host-disk.md) |
| k3dm Host Pod IP Pool | `k3dm-host-cni-ipam` | `platform-ops/grafana-dashboard-host-cni-ipam.yaml` | `grafana-dashboards-hub` ApplicationSet | hub | [Reference](grafana-dashboards/k3dm-host-cni-ipam.md) |
| k3dm PR Checks | `k3dm-pr-checks` | `platform-ops/grafana-dashboard-pr-checks.yaml` | `grafana-dashboards-hub` ApplicationSet | hub | [Reference](grafana-dashboards/k3dm-pr-checks.md) |
| k3dm Alertmanager Delivery | `k3dm-alertmanager-delivery` | `platform-ops/grafana-dashboard-alertmanager-delivery.yaml` | `grafana-dashboards-hub` ApplicationSet | hub | [Reference](grafana-dashboards/k3dm-alertmanager-delivery.md) |
| k3dm Agent Dispatch | `k3dm-agent-dispatch` | `platform-ops/grafana-dashboard-agent-dispatch.yaml` | `grafana-dashboards-hub` ApplicationSet | hub | [Reference](grafana-dashboards/k3dm-agent-dispatch.md) |
| k3dm Bug Tracking | `k3dm-bugs` | `platform-ops/grafana-dashboard-bugs.yaml` | `grafana-dashboards-hub` ApplicationSet; `make platform-ops` | hub | [Reference](grafana-dashboards/k3dm-bugs.md) |
| k3dm Deployment Metrics | `k3dm-deployments` | `etc/grafana/dashboards/k3dm-deployments-configmap.yaml` | `make observability-acg` | ACG | [Reference](grafana-dashboards/k3dm-deployments.md) |
| k3dm Tests | `k3dm-tests` | `etc/grafana/dashboards/k3dm-tests-configmap.yaml` | `grafana-dashboards-hub` and `grafana-dashboards-acg` ApplicationSets | hub + ACG | [Reference](grafana-dashboards/k3dm-tests.md) |
| Trivy Security | `trivy-security` | `etc/grafana/dashboards/trivy-security-configmap.yaml` | `make observability-acg` | ACG | [Reference](grafana-dashboards/trivy-security.md) |
| Checkout Load Test | `checkout-loadtest` | `etc/grafana/dashboards/checkout-loadtest-configmap.yaml` | `grafana-dashboards-acg` ApplicationSet | app clusters except hub | [Reference](grafana-dashboards/checkout-loadtest.md) |
| Grafana Health & Firing Alerts | `k3dm-grafana-health` | `platform-ops/grafana-dashboard-overview-readable.yaml`; `etc/grafana/dashboards/grafana-overview-readable-configmap.yaml` | hub and ACG dashboard ApplicationSets | hub + ACG | [Source definition](../../scripts/etc/argocd/platform-ops/grafana-dashboard-overview-readable.yaml) |
| k3dm VectorDB Health | `k3dm-vectordb` | `platform-ops/grafana-dashboard-vectordb.yaml` | `grafana-dashboards-hub` ApplicationSet | hub | [Reference](grafana-dashboards/k3dm-vectordb.md) |

Public endpoint probes (`probe_*`) are Prometheus blackbox-exporter metrics and `Probe` resources, not Grafana dashboards. See [probe triage](grafana-dashboards/shared-operations.md#triage-no-data-by-cause).

## Choosing a Grafana instance

The repository ships separate hub and ACG Grafana instances, with dashboards placed according to their data. The public `grafana.3ai-talk.org` route should reach hub Grafana. Confirm the instance before debugging a missing dashboard or empty panel; the [health dashboard](grafana-dashboards/shared-operations.md#which-grafana-am-i-looking-at) explains the stock Grafana Overview distinction.

All dashboard ConfigMaps use the `grafana_dashboard: "1"` label in the `monitoring` namespace for sidecar discovery. A missing dashboard points first to deployment, namespace, or label; a loaded dashboard with empty panels points first to its producer.

In the k3dm Bug Tracking dashboard, use the funnel icon in the **Bug** column header to filter rows by title. If the table is empty with no column filter selected, there are no `k3dm_bug_info` series for the current repository, release, and verification selections; check telemetry ingestion before concluding that a bug is missing.

## CVE Auto-Patch triage

| Symptom | Meaning | Check |
|---|---|---|
| **Our images with no Trivy report** has a row | The critical-CVE table cannot vouch for that running image because no VulnerabilityReport exists | Check the app-cluster Trivy Operator scan jobs and report in the listed namespace; findings panels cannot show an unscanned image |

## Shared operations

- [Producer chain and provenance](grafana-dashboards/shared-operations.md#the-producer-chain)
- [No data triage](grafana-dashboards/shared-operations.md#triage-no-data-by-cause)
- [Adding or changing a dashboard](grafana-dashboards/shared-operations.md#adding-or-changing-a-dashboard)
- [Where to look next](grafana-dashboards/shared-operations.md#where-to-look-next)
