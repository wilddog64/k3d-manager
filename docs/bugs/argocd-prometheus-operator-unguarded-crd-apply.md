# Bug: argocd.sh applies Prometheus-Operator CRs without a CRD guard — aborts fresh-hub `make up`

## Symptom

On a **fresh hub** (no monitoring stack / Prometheus Operator yet), `make up` aborts during the
ArgoCD platform-ops deploy:

```
INFO: [argocd] Deploying PrometheusRule...
error: resource mapping not found for name: "argocd-degraded" namespace: "cicd" from
".../scripts/etc/argocd/platform-ops/prometheusrule.yaml":
no matches for kind "PrometheusRule" in version "monitoring.coreos.com/v1"
ensure CRDs are installed first
ERROR: failed to execute kubectl apply -f .../prometheusrule.yaml: 1
WARN: [acg-up] failed (exit 1) — cleaning up local processes...
make: *** [up] Error 1
```

Because the deploy aborts here, **`register_app_cluster` (bin/cluster-up:758) never runs** — the app
cluster is never registered into the hub ArgoCD, no ApplicationSets/Applications are created, and the
whole bring-up is blocked. Observed live 2026-09-04 on the v1.28.0 two-cloud validation (AWS EC2 k3s +
hostinger): both clouds' nodes and the hub came up, but ArgoCD stayed bare.

## Root cause

`scripts/plugins/argocd.sh` (platform-ops deploy) applies a run of **monitoring-stack-dependent**
resources **without any guard**, unlike the ServiceMonitor ensure at lines 512–515 which correctly skips
when the CRD is absent. Two distinct preconditions are involved, both supplied only once the monitoring
stack (kube-prometheus-stack) is installed:

- **needs the Prometheus-Operator CRDs** (`monitoring.coreos.com`):
  - `prometheusrule.yaml` → `PrometheusRule` (`/v1`)
  - `alertmanager-config.yaml` → `AlertmanagerConfig` (`/v1alpha1`)
  - `vulnerability-inventory-exporter.yaml` → bundles a `ServiceMonitor` (`/v1`)
- **needs the `monitoring` namespace** (Grafana dashboard ConfigMaps, `namespace: monitoring`):
  - `grafana-dashboard-argocd.yaml`, `grafana-dashboard-cve-autopatch.yaml`, `grafana-dashboard-e2e.yaml`

The CRDs and the `monitoring` namespace both arrive with the monitoring stack, which is synced *after*
ArgoCD is up — so on a fresh hub all of these precede their prerequisites and hard-fail. `PrometheusRule`
is simply the first reached; fixing it alone exposes the next (`grafana-dashboard-argocd.yaml` →
`namespaces "monitoring" not found`), then the trailing dashboards. All six belong behind one guard.

## Fix

Mirror the existing ServiceMonitor guard (argocd.sh:512–515): wrap the whole run of
monitoring-stack-dependent applies behind a guard that checks **both** preconditions — the
Prometheus-Operator CRD **and** the `monitoring` namespace — and skip with one info log when either is
absent. (Copilot flagged 2026-09-04 on PR #119 that a CRD-only check would still let the dashboard
ConfigMap applies fail if the CRDs exist cluster-wide but `monitoring` was deleted; checking both matches
the log message and the resources' true prerequisites.):

```bash
   if _kubectl --no-exit get crd prometheusrules.monitoring.coreos.com >/dev/null 2>&1 && \
      _kubectl --no-exit get namespace monitoring >/dev/null 2>&1; then
      _info "[argocd] Deploying PrometheusRule..."
      _kubectl apply -f "${_dir}/prometheusrule.yaml"

      _info "[argocd] Deploying Grafana dashboard (ArgoCD apps + image-updater sync)..."
      _kubectl apply -f "${_dir}/grafana-dashboard-argocd.yaml"

      _info "[argocd] Deploying AlertmanagerConfig..."
      _kubectl apply -f "${_dir}/alertmanager-config.yaml"

      _info "[argocd] Deploying vulnerability inventory exporter..."
      _kubectl apply -f "${_dir}/vulnerability-inventory-exporter.yaml"
      _kubectl rollout restart deployment/vulnerability-inventory-exporter -n platform-ops >/dev/null 2>&1 || true

      _info "[argocd] Deploying CVE auto-patch Grafana dashboard..."
      _kubectl apply -f "${_dir}/grafana-dashboard-cve-autopatch.yaml"

      _info "[argocd] Deploying E2E verification Grafana dashboard..."
      _kubectl apply -f "${_dir}/grafana-dashboard-e2e.yaml"
   else
      _info "[argocd] Prometheus-Operator CRDs / monitoring namespace absent; skipping PrometheusRule, AlertmanagerConfig, inventory-exporter, and Grafana dashboards (monitoring stack not yet installed)"
   fi
```

The exporter `rollout restart` moves inside the guard too (nothing to restart when the exporter was
skipped). `grafana-admin-externalsecret.yaml` and `grafana-credential-rotator.yaml` are NOT applied here —
they belong to `observability.sh` (the monitoring stack), so they need no guard in this path.

Once the monitoring stack is installed (CRDs + `monitoring` namespace present), a subsequent idempotent
`make up` applies all of these normally — no manual step needed.

## Definition of Done

- [ ] Guard checks BOTH the Prometheus-Operator CRD AND the `monitoring` namespace, wrapping ALL monitoring-stack-dependent applies in the platform-ops deploy:
      `PrometheusRule`, `AlertmanagerConfig`, `vulnerability-inventory-exporter` (+ its rollout restart),
      and the three Grafana dashboard ConfigMaps (`argocd`, `cve-autopatch`, `e2e`).
- [ ] `shellcheck scripts/plugins/argocd.sh` clean (no new warnings).
- [ ] Fresh-hub `make up` proceeds past the platform-ops deploy and reaches `register_app_cluster`
      (live-verified on the v1.28.0 two-cloud bring-up).

## What NOT to do

- Do NOT install the Prometheus-Operator CRDs / `monitoring` namespace from this code path just to satisfy
  the applies — the monitoring stack owns them; the fix is to skip gracefully, matching the ServiceMonitor
  pattern.
- Do NOT `|| true` the applies — that would silently swallow real errors when the prerequisites *are*
  present.
- Do NOT leave the Grafana dashboard ConfigMaps unconditional — they target `namespace: monitoring`, which
  is absent on a fresh hub, and fail the same way as the CRs.
