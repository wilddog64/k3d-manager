# Hub `grafana-dashboard-overview-readable` ConfigMap is owned by two ArgoCD apps

**Filed:** 2026-10-01
**Branch:** `k3d-manager-v1.40.0`
**Severity:** low–medium. The hub's Readable Overview dashboard can flip between two different
dashboard bodies, and `k3d-cluster-grafana-dashboards` shows OutOfSync permanently. That drift is
also why the two copies diverged (see `docs/bugs/2026-10-01-grafana-overview-raw-series-labels.md`).
**Status:** FIXED (Codex, 2026-10-01)

## Observed (live hub, 2026-10-01, read-only)

- `k3d-cluster-grafana-dashboards`: Sync `OutOfSync`, Health `Healthy`, last op `Succeeded`.
  Condition `SharedResourceWarning`: "ConfigMap/grafana-dashboard-overview-readable is part of
  applications cicd/k3d-cluster-grafana-dashboards and hub-grafana-dashboards".
- That ConfigMap (`monitoring/grafana-dashboard-overview-readable`) is the only resource on the hub
  owned by more than one Application.
- The live object's `argocd.argoproj.io/tracking-id` belongs to `hub-grafana-dashboards`. The two
  apps synced 2 s apart (02:01:34Z / 02:01:36Z) after the same push, and the hub copy won.

## Cause

The hub is registered with ArgoCD twice:

- Implicitly, as the in-cluster target `https://kubernetes.default.svc`. `grafana-dashboards-hub`
  (`scripts/etc/argocd/applicationsets/grafana-dashboards-hub.yaml`) uses this to sync
  `scripts/etc/argocd/platform-ops/`. That folder contains
  `grafana-dashboard-overview-readable.yaml`.
- Explicitly, as cluster secret `ubuntu-k3s-app-cluster` (name `k3d-cluster`, server
  `https://kubernetes.default.svc`, label `k3d-manager/role: app-cluster`).
  `grafana-dashboards-acg` (`scripts/etc/argocd/applicationsets/grafana-dashboards-acg.yaml`)
  selects that label and syncs `scripts/etc/grafana/dashboards/`. That folder contains
  `grafana-overview-readable-configmap.yaml`, a ConfigMap with the **same name and namespace**.

The `app-cluster` registration cannot be removed: four AppSets, including ESO, select it (memory:
`reference_hub_app_cluster_registration_is_load_bearing_for_eso`). The two files also differ
outside the Build Info panel (`fieldConfig`, `justifyMode`/`orientation`, and the
`release: kube-prometheus-stack` label), so the app that does not own the ConfigMap always sees a
diff.

`make fix-sync APP=k3d-cluster-grafana-dashboards` is **not** a fix. It hands ownership to the app
copy, puts `hub-grafana-dashboards` OutOfSync, and with `selfHeal` on both apps they can overwrite
each other.

## Fix

Make `hub-grafana-dashboards` the only writer of this ConfigMap on the hub, and keep app clusters
(ubuntu-hostinger) on the app copy.

1. `grafana-dashboards-acg.yaml`: when the generated cluster is the in-cluster hub, exclude every
   file in `scripts/etc/grafana/dashboards/` whose ConfigMap `metadata.name` also exists in
   `scripts/etc/argocd/platform-ops/`. Today that is only `grafana-overview-readable-configmap.yaml`.
   Key the condition on the **server** (`{{.server}}` equals `https://kubernetes.default.svc`),
   never on the cluster name: names get renamed (memory:
   `reference_cluster_registration_rename_breaks_hardcoded_context_gates`). Use the existing
   `goTemplate: true` and `missingkey=error`. A templated `directory.exclude` must render to an empty
   string for non-hub clusters.
2. Do not rename the ConfigMap, the dashboard `uid`, or either file. Do not touch
   `grafana-dashboards-hub.yaml`, the platform-ops copy, or the cluster registration.

## Resolution

`grafana-dashboards-acg` now excludes the colliding dashboard file only when the generated
cluster server is `https://kubernetes.default.svc`; app clusters continue to render the app copy.
The exclusion is derived by the offline BATS collision guard and uses Argo CD's directory glob
semantics with a brace-form single-file pattern. The non-hub Go-template branch renders an empty,
valid `exclude` string.

Prune-safety operator note: `k3d-cluster-grafana-dashboards` has `prune: true`. After the reapply
it no longer renders the file. ArgoCD prunes only objects whose tracking id names that app. Today
the live ConfigMap's tracking id names `hub-grafana-dashboards`, so the reapply removes nothing.
Before reapplying, confirm that with:

`kubectl -n monitoring get cm grafana-dashboard-overview-readable -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/tracking-id}'`

If it names `k3d-cluster-grafana-dashboards`, sync `hub-grafana-dashboards` first.

## Tests

Offline BATS in `scripts/tests/plugins/grafana_dashboard_appsets.bats`, with no cluster:

- **Collision guard (derived, not hardcoded):** collect ConfigMap `metadata.name` values from
  `scripts/etc/argocd/platform-ops/*.yaml` and from `scripts/etc/grafana/dashboards/*.yaml`. For
  every name in both, the file under `grafana/dashboards/` that holds it must appear in the
  `grafana-dashboards-acg.yaml` hub exclude.
- The exclude is conditional on `.server` and the in-cluster URL. Assert those tokens, not a whole
  source line.
- If `argocd appset generate` is not available offline, do not invent a renderer. A Go-template
  render is optional: only if a pinned tool already in the repo does it.

Mutations, each red and then `cp`-restored and `cmp`-proved:
(a) remove the exclude → collision guard red;
(b) key the condition on `.name` instead of `.server` → red;
(c) in a BATS temp copy of the platform-ops dir, add a second colliding ConfigMap name → red.
