# Bug: vector-store metrics go to the app cluster, so the hub dashboard and alerts never see them

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-30 by Claude (cloud session), from the operator's "why this still has no data?"
**Status:** OPEN — assigned to Codex 2026-09-30 (brief below)
**Severity:** Medium. The dashboard in the Grafana the operator uses is blank, and the vectordb alerts
evaluate on a Prometheus that never receives the metrics.
**Related:** `2026-09-30-vectordb-index-never-refreshes-automatically.md` (it noted the hub-vs-app-cluster
placement as a separate issue); `2026-06-09-pushgateway-deployment-metrics-gap.md` (a different job on
the same app-cluster Pushgateway).

## Evidence (2026-09-30)

- The hub Grafana (`grafana.3ai-talk.org`) *k3dm VectorDB Health*: every panel "No data".
- `curl localhost:9091/metrics` on the M4: `k3dm_vectordb_rows 1730` and all
  `k3dm_vectordb_index_last_result` series present.
- hostinger Prometheus `k3dm_vectordb_rows` → 1730, current. The hostinger Grafana, reached through a
  port-forward plus an SSH tunnel, shows full data.
- ConfigMap `monitoring/k3dm-vectordb` exists on **both** clusters (age 3d20h).

## Root cause

The vector store runs on the hub (`vectordb` namespace), but its metrics take the app-cluster path:
Hermes and `bin/k3dm-vectordb-metrics` push to `localhost:9091`, which `bin/cluster-up` forwards to the
**app cluster's** Pushgateway; the dashboard ships through `grafana-dashboards-acg`. Meanwhile
`observability.sh` applies `scripts/etc/prometheus/rules/*.yaml`, including `vectordb.yaml`
(`cluster: hub`), to the **hub**. So:

1. The hub Grafana's copy queries the hub Prometheus, which has no vectordb series.
2. The vectordb alerts evaluate on the hub, where the metrics are absent.
3. The metrics follow whichever app cluster `localhost:9091` points at. On 2026-09-29 it pointed at an
   expired ACG sandbox and every panel went blank.

## Decision (operator, 2026-09-30)

Option 1: publish vectordb metrics on the **hub** and show the dashboard there. The app-cluster
Pushgateway keeps its other jobs (`k3dm-tests`, deployment metrics) unchanged.

## Codex brief

**Goal:** the hub Grafana's *k3dm VectorDB Health* shows live data with no tunnel. The vectordb alerts
evaluate against real series. Nothing vectordb-related depends on the app cluster any more.

**Runs where:** Codex web is fine. Offline only: no cluster, helm, launchctl or network calls.

**Files to touch (only these):**
- `scripts/etc/argocd/applicationsets/observability.yaml`: add a list element `hub-pushgateway`
  (namespace `monitoring`, chart `prometheus-pushgateway`, repoURL
  `https://prometheus-community.github.io/helm-charts`, `targetRevision: 2.14.0` — the version
  `_deploy_pushgateway_acg` already pins, valuesFile
  `scripts/etc/helm/observability/pushgateway-hub-values.yaml`). Touch nothing else in the file.
- `scripts/etc/helm/observability/pushgateway-hub-values.yaml` (new): `fullnameOverride:
  prometheus-pushgateway` (so the Service is `monitoring/prometheus-pushgateway`, same as on the app
  cluster), `service.type: ClusterIP`, `replicaCount: 1`, modest `resources.requests`. No
  `serviceMonitor` (the static scrape below owns it).
- `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`: append one
  `additionalScrapeConfigs` job, copied from the ACG values:
  `job_name: pushgateway`, `honor_labels: true`, `static_configs: targets:
  ['prometheus-pushgateway.monitoring:9091']`. `honor_labels` is required: the dashboard and
  `VectorDBMetricsStale` key on `job="k3dm-vectordb"`. Keep every other line exactly as it is.
- `scripts/etc/launchd/com.k3d-manager.hub-pushgateway-port-forward.plist.tmpl` (new), modelled on
  `com.k3d-manager.prometheus-port-forward.plist.tmpl`: `kubectl port-forward
  svc/prometheus-pushgateway 19094:9091 -n monitoring --context k3d-k3d-cluster`, `KeepAlive`,
  `RunAtLoad`, logs under `~/Library/Logs/k3dm-hub-pushgateway-port-forward.log`. Port **19094** is
  unused (19090/19091/19093/19190 are taken).
- `Makefile`: `install-hub-pushgateway-port-forward` and `uninstall-hub-pushgateway-port-forward`,
  the same shape as the prometheus pair; add both to `.PHONY` and to `make help`.
- `bin/k3dm-vectordb-metrics` and `bin/k3dm-hermes` (`_push_index_metrics`): read
  `K3DM_VECTORDB_PUSHGATEWAY_URL`, default `http://localhost:19094`. **Do not** change
  `K3DM_PUSHGATEWAY_URL` or any other user of `localhost:9091` (webhook, `k3dm-test-metrics`, smoke).
- Dashboard move: create `scripts/etc/argocd/platform-ops/grafana-dashboard-vectordb.yaml`
  (ConfigMap `grafana-dashboard-vectordb`, namespace `monitoring`, labels `grafana_dashboard: "1"`
  and `release: kube-prometheus-stack` like the alertmanager-delivery one), with the dashboard JSON
  byte-for-byte from `scripts/etc/grafana/dashboards/k3dm-vectordb-configmap.yaml` (keep `uid:
  k3dm-vectordb`, the instant queries and the layout). Delete the old file; ArgoCD prune then removes
  the app-cluster copy. Add the `_kubectl apply -f "${_dir}/grafana-dashboard-vectordb.yaml"` line in
  `scripts/plugins/argocd.sh` next to the alertmanager-delivery one. `grafana-dashboards-hub` already
  includes `grafana-dashboard-*.yaml`.
- Tests: `scripts/tests/plugins/vectordb_rules.bats` (point `DASHBOARD` at the new path),
  `scripts/tests/hermes/test_vectordb_sensor.py` and `scripts/tests/hermes/test_hermes.py`, plus a
  new `scripts/tests/plugins/hub_pushgateway.bats`.
- Docs: `docs/guides/vector-store.md` (where metrics go, the port-forward, the one-time steps below),
  `CHANGELOG.md`, `memory-bank/activeContext.md`, `memory-bank/progress.md`, this doc (Status → FIXED).

**Tests (offline):**
1. `bin/k3dm-vectordb-metrics` and Hermes `_push_index_metrics` post to
   `http://localhost:19094/metrics/job/k3dm-vectordb` and `…/k3dm-vectordb-index` by default, and honour
   `K3DM_VECTORDB_PUSHGATEWAY_URL`. Setting only `K3DM_PUSHGATEWAY_URL` does **not** redirect them.
2. `observability.yaml` has the `hub-pushgateway` element with `targetRevision: 2.14.0`; the values file
   sets `fullnameOverride: prometheus-pushgateway`.
3. The hub values' scrape job `pushgateway` has `honor_labels: true` and the target
   `prometheus-pushgateway.monitoring:9091`. Parse the YAML; don't grep.
4. `make -n install-hub-pushgateway-port-forward` renders a plist containing `19094:9091`,
   `svc/prometheus-pushgateway` and `k3d-k3d-cluster`, and never `9091:9091`.
5. The dashboard exists only at the platform-ops path, is applied by `argocd.sh`, keeps
   `uid: k3dm-vectordb`, and its JSON equals the old file's JSON (compare parsed objects).
   `scripts/etc/grafana/dashboards/` has no vectordb file.
6. No other `localhost:9091` user changed: `git grep -n 'localhost:9091'` lists the same files as
   before, minus the two vectordb publishers.

**Mutations (paste each red run, then green):** leave the default at `localhost:9091` → test 1 red;
drop `honor_labels` → test 3 red; forward `9091:9091` → test 4 red; keep the old dashboard file →
test 5 red; route through `K3DM_PUSHGATEWAY_URL` → test 1 red.

**Gates (paste output):** `make test-pytest`; the touched BATS suites; `python3 scripts/check-doc-links.py`;
`kubeconform -strict -ignore-missing-schemas` on the new dashboard; `git diff --stat` lists only the
files above.

**Lessons from earlier reviews:** do not re-indent or restructure YAML you were not asked to touch
(`29b7f55c` broke a whole PrometheusRule that way); tests must not read the host's Keychain or network;
every early-return path has a test; cover every numbered test or say which one you skipped and why.

**Do not change:** the app-cluster Pushgateway, `bin/cluster-up`'s `localhost:9091` forward,
`K3DM_PUSHGATEWAY_URL`, `scripts/etc/prometheus/rules/vectordb.yaml`, the dashboard JSON content,
`scripts/lib/foundation/`.

**Commit and hand back:** one commit on `k3d-manager-v1.40.0`, message
`fix(vectordb): publish vector-store metrics on the hub and move its dashboard there`.
No PR, no merge, no force-push, no `--no-verify`.

## Operator steps after it lands (one time)

1. ArgoCD syncs `hub-pushgateway`, the hub Prometheus scrape job and the dashboard (all on
   `k3d-manager-v1.40.0`, already the tracked branch).
2. `make install-hub-pushgateway-port-forward`, then `curl -s localhost:19094/-/healthy`.
3. Remove the stray hub copy **after** checking who owns it:
   `kubectl --context k3d-k3d-cluster -n monitoring get configmap k3dm-vectordb -o jsonpath='{.metadata.annotations}{"\n"}{.metadata.labels}{"\n"}'`.
   If no ArgoCD Application tracks it, delete it: it has the same dashboard `uid` as the new one.
4. After one Hermes poll, the hub *k3dm VectorDB Health* shows data.
