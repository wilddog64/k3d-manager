# Bug: hub `federate-acg` scrapes the hub itself, duplicating every series as `cluster="acg"`

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-13
**Status:** OPEN — assigned to Codex
**Files:** `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`, `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml`, `scripts/tests/plugins/observability_federate_self_scrape.bats` (new), `CHANGELOG.md`
**Related:** `docs/bugs/archive/2026-08-20-pre-v1.26/2026-06-06-prometheus-oomkill-federation-too-broad.md`

## Problem

The "Image Updater Ready/Desired Replicas" stat panels on the hub ArgoCD dashboard show `1 1 1 1 1` instead of `1`. The root cause is broader than the panel.

**1. `federate-acg` scrapes the hub.**
- The hub's `federate-acg` job (`kube-prometheus-stack-values.yaml`) scrapes `host.internal:19090/federate` for `node-exporter|kubelet|kube-state-metrics|istiod|envoy`, and adds the target label `cluster: acg`.
- Port 19090 is claimed by two things:
  - `bin/cluster-up` / `bin/cluster-refresh` port-forward the **ACG** Prometheus there.
  - LaunchAgent `com.k3d-manager.prometheus-port-forward` (`KeepAlive`) port-forwards the **hub** Prometheus there (`--context k3d-k3d-cluster`); cloudflared `prometheus.3ai-talk.org` depends on it.
- With no ACG sandbox, the target is `up` and returns the hub's own series.
- The ACG Prometheus sets `externalLabels.cluster: ubuntu-k3s`, so genuine ACG series keep `cluster=ubuntu-k3s` under `honor_labels: true`. The hub has no `cluster` external label, so its self-scraped copies take the target label `cluster="acg"`.

**2. Live evidence (2026-09-13, no ACG sandbox running).**
- `count by (cluster)({job=~"node-exporter|kubelet|kube-state-metrics|istiod|envoy"})`: `{}` 81538 and `{cluster="acg"}` 81540. The hub stores these series twice.
- `kube_deployment_spec_replicas{namespace="cicd",deployment="argocd-image-updater"}` returns two series from the same kube-state-metrics pod. The second adds `cluster="acg"`, `prometheus`, `prometheus_replica`.
- Firing alerts duplicated with `cluster="acg"`: `KubeJobFailed` (3 + 3) and `TargetDown` (1 + 2). `PrometheusDuplicateTimestamps` and `PrometheusOutOfOrderTimestamps` are also firing.
- Grafana datasource `acg-prometheus` (`http://host.internal:19090`) likewise shows hub data. That is out of scope here.

**3. The stat panels.** They use the raw series with `reduceOptions.calcs: lastNotNull`, so any duplicate series (this one, or a kube-state-metrics pod restart) renders as several values.

## Fix

### S1 — `kube-prometheus-stack-values.yaml`: drop self-scraped samples in `federate-acg`

Old:

```yaml
        static_configs:
          - targets:
              - 'host.internal:19090'
            labels:
              cluster: acg
```

New:

```yaml
        static_configs:
          - targets:
              - 'host.internal:19090'
            labels:
              cluster: acg
        metric_relabel_configs:
          - source_labels: [cluster]
            regex: acg
            action: drop
```

- Genuine ACG samples carry the ACG external label `cluster=ubuntu-k3s` (it wins under `honor_labels: true`), so they are kept.
- Samples without a source `cluster` label end up with `cluster="acg"` and are dropped. That is exactly the hub self-scrape.
- Leave the target label as is: it still marks the scrape pool, and no rule or dashboard in the repo selects `cluster="acg"`.

### S2 — `grafana-dashboard-argocd.yaml`: aggregate the two replica stats

Old:

```
              "expr": "kube_deployment_status_replicas_available{namespace=\"cicd\",deployment=\"argocd-image-updater\"}",
```

New:

```
              "expr": "max(kube_deployment_status_replicas_available{namespace=\"cicd\",deployment=\"argocd-image-updater\",cluster!=\"acg\"})",
```

Old:

```
              "expr": "kube_deployment_spec_replicas{namespace=\"cicd\",deployment=\"argocd-image-updater\"}",
```

New:

```
              "expr": "max(kube_deployment_spec_replicas{namespace=\"cicd\",deployment=\"argocd-image-updater\",cluster!=\"acg\"})",
```

Change no other panel.

### S3 — tests: `scripts/tests/plugins/observability_federate_self_scrape.bats` (new)

Use `yq -r` (mikefarah v4, as in `grafana_dashboard_appsets.bats`) and `jq`. Assert tokens only; never `grep -F` a whole source line.

1. **`federate-acg` drops self-scraped samples.**
   - Select the job: `yq -r '.prometheus.prometheusSpec.additionalScrapeConfigs[] | select(.job_name == "federate-acg") | .metric_relabel_configs[0].action'`.
   - Expect `drop`.
   - In the same way, `.source_labels[0]` = `cluster` and `.regex` = `acg`.
2. **`federate-acg` still labels the target `acg` and honors source labels.** `.static_configs[0].labels.cluster` = `acg` and `.honor_labels` = `true`.
3. **The replica stats aggregate.**
   - Extract the dashboard JSON: `yq -r '.data["argocd-image-updater-hub.json"]'`.
   - For each panel title `Image Updater Ready Replicas` and `Image Updater Desired Replicas`, `jq -r '.panels[] | select(.title == "<title>") | .targets[0].expr'`:
     - starts with `max(`;
     - contains `cluster!="acg"`.
4. **The dashboard JSON parses.** `jq -e '.panels | length > 0'` on the extracted JSON.

## CHANGELOG

Under `## [Unreleased]` → `### Fixed`, as the last bullet of that section:

```
- Hub Prometheus no longer stores every node-exporter/kubelet/kube-state-metrics/istiod/envoy series twice: `federate-acg` scrapes `host.internal:19090`, which serves the hub's own Prometheus whenever no ACG sandbox holds that port, so the self-scraped copies (labelled `cluster="acg"`) duplicated alerts such as `KubeJobFailed`/`TargetDown`; the job now drops samples that do not carry the ACG Prometheus's own `cluster` external label, and the ArgoCD dashboard's Image Updater replica stats aggregate with `max()`
```

## Definition of Done

- [ ] S1–S3 applied; no other lines changed in the two config files.
- [ ] `yq -e . scripts/etc/helm/observability/kube-prometheus-stack-values.yaml >/dev/null` and `yq -e . scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml >/dev/null` both exit 0.
- [ ] `bats scripts/tests/plugins/observability_federate_self_scrape.bats scripts/tests/plugins/argocd_metrics_servicemonitor.bats scripts/tests/plugins/argocd_loki.bats`: all pass (paste the summary).
- [ ] CHANGELOG bullet added.
- [ ] Commit message, verbatim: `fix(observability): drop hub self-scrape in federate-acg and aggregate replica stats`
- [ ] Pushed; `git rev-parse origin/k3d-manager-v1.34.0` equals the commit SHA.

## Live rollout (operator; NOT for Codex)

- **Values (S1):** read by the hub `observability` ApplicationSet from the values branch.
  - Run `argocd_check_values_branch` first.
  - If the hub still points at an older branch, reapply ONLY the `observability` ApplicationSet with `K3D_MANAGER_BRANCH=k3d-manager-v1.34.0`, never all sets.
  - Then confirm `count({cluster="acg"})` falls to 0 within ~5 minutes (samples age out with retention; new ones stop immediately).
- **Dashboard (S2):** `kubectl --context k3d-k3d-cluster apply -f scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml`.

## Not in this fix

- **The port-19090 collision itself.** The hub LaunchAgent and the ACG port-forward both want `localhost:19090`, and cloudflared, `loadtest.sh`, `bin/k3dm-webhook` and Hermes `repairs.py` each assume one or the other. Giving ACG federation its own port is a separate design change.
- **Grafana datasource `acg-prometheus`** points at the hub when no ACG sandbox is up.

## What NOT to Do

- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`.
- Do NOT run `kubectl`, `helm`, `launchctl` or any `k3d-manager` command against a live cluster.
- Do NOT change ports, LaunchAgent templates, cloudflared config, `bin/cluster-up`, `bin/cluster-refresh`, the ACG values file, `scripts/lib/foundation/`, `scripts/lib/acg/`, or memory-bank.
- Do NOT `grep -F` whole source lines in BATS.
