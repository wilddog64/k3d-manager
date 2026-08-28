# Monitoring pause/resume toggle — reclaim ~1.1 CPU cores on demand

**Date:** 2026-08-28
**Status:** DONE 2026-08-28 — implemented + live-verified (pause durable through a
40s selfHeal window; resume restores all workloads to 1 without waiting on ArgoCD).
**Area:** `scripts/plugins/observability.sh`, `Makefile`,
`scripts/etc/argocd/applicationsets/observability.yaml`
**Severity:** Enhancement (dev-box CPU relief) — no functional bug.

## Motivation

The hub is a single-host **k3d** cluster on a fanless M4 Air, chronically CPU
overcommitted (~1.27× on a 10-core box). The single largest steady consumer is
the observability stack, which runs a **production-grade collection posture** on
a machine where nobody pages on the data. Live snapshot (2026-08-28):

| Pod | CPU |
|-----|-----|
| `prometheus-kube-prometheus-stack-prometheus-0` | 730m |
| `kube-prometheus-stack-grafana` | 273m |
| `alertmanager-...-alertmanager-0` | 37m |
| `kube-prometheus-stack-kube-state-metrics` | 18m |
| node-exporters (DaemonSet) | ~15m |
| **reclaimable total** | **~1.1 cores** |

Config-tuning levers are **already spent**: `scrapeInterval: 60s`,
`retention: 3d`, Loki monolithic with caches off, most `defaultRules` and the
control-plane scrape jobs disabled. Trivy is event-driven (`scanJobTTL: 1h`),
not a cron, so it is near-idle on a stable cluster. The remaining lever is an
**on-demand pause** so the whole ~1.1 cores can be reclaimed on quiet days and
brought back for a debugging session.

## The two-controller constraint

The stack is GitOps-managed. A naive `kubectl scale --replicas=0` is reverted
by **three** distinct mechanisms, all of which the toggle must defeat:

1. **Application controller `selfHeal: true`** — the observability Applications
   (`kube-prometheus-stack`, `hub-loki`, `trivy-operator` in ns `cicd`) each
   have `syncPolicy.automated.selfHeal: true`, so ArgoCD re-applies the
   declared replica count within a sync cycle.
2. **ApplicationSet controller** — those Applications are owned by the
   `observability` ApplicationSet (ArgoCD v3.5.1), whose controller re-templates
   the Application spec (including `syncPolicy`) back to the generator template
   within seconds. So merely patching an Application's `syncPolicy.automated`
   does **not** stick — and the Application-level `skip-reconcile` annotation is
   itself stripped by the same re-templating (verified live). The durable fix is
   an **ApplicationSet-level** `ignoreApplicationDifferences` on
   `/spec/syncPolicy/automated`, committed to `observability.yaml`, which tells
   the ApplicationSet controller to leave that field alone so the pause patch
   sticks.
3. **prometheus-operator** — the `prometheus` and `alertmanager` StatefulSets
   are not plain workloads; they are reconciled from the `Prometheus` /
   `Alertmanager` CRs by `kube-prometheus-stack-operator`. Scaling those
   StatefulSets directly is reverted by the operator.

## Mechanism (defeats all three)

**Prerequisite (committed once):** the `observability` ApplicationSet carries
`ignoreApplicationDifferences: [{jsonPointers: [/spec/syncPolicy/automated]}]`,
so the ApplicationSet controller stops re-templating that field and the pause
patch below sticks.

**Pause** (`observability_pause`):
1. For each of the 3 Applications: `kubectl patch application` merge-null its
   `spec.syncPolicy.automated` (stops the **Application** controller's selfHeal;
   durable because the ApplicationSet ignores that path).
2. Scale the `kube-prometheus-stack-operator` Deployment to 0 **first**, so it
   stops reconciling the prometheus/alertmanager StatefulSets.
3. Scale every remaining Deployment and StatefulSet in namespaces `monitoring`
   and `trivy-system` to 0 (name-agnostic — those namespaces are dedicated to
   the stack). node-exporter is a DaemonSet (~15m, negligible) and is left
   running.

**Resume** (`observability_resume`):
1. For each of the 3 Applications: `kubectl patch application` its
   `spec.syncPolicy.automated` back to `{prune: true, selfHeal: true}` (re-arms
   selfHeal as the safety net).
2. Scale workloads back **explicitly** — do **not** wait on an ArgoCD sync,
   which is slow or reports `Unknown` exactly when the node is CPU-starved (the
   condition this feature operates under; verified live). Operator Deployment
   first, then the prometheus/alertmanager CRs to `replicas: 1`, then every
   Deployment/StatefulSet in the namespaces to `1`. The single-node hub runs one
   replica of each; the re-armed selfHeal corrects any true desired count on the
   next reconcile.
3. Hard-refresh each Application (`argocd.argoproj.io/refresh=hard`) so ArgoCD
   recomputes and settles to `Synced`.

Both functions are **idempotent** and warn+return 0 on any missing prerequisite
(absent Application, absent namespace) — never a hard failure.

## Invocation

```bash
./scripts/k3d-manager observability_pause     # reclaim ~1.1 cores
./scripts/k3d-manager observability_resume    # bring the stack back
make monitoring-pause
make monitoring-resume
```

## Config vars (overridable)

- `OBSERVABILITY_HUB_CONTEXT` (default `k3d-k3d-cluster`)
- `ARGOCD_NAMESPACE` (default `cicd`) — where the Applications live
- `OBSERVABILITY_APPS` (default `kube-prometheus-stack hub-loki trivy-operator`)
- `OBSERVABILITY_WORKLOAD_NS` (default `monitoring trivy-system`)

## Why this is safe

- **Reversible and GitOps-consistent.** Pause only *suspends* management +
  scales to zero; resume hands control back to ArgoCD, which reconciles from the
  committed chart values — the single source of truth is unchanged. Nothing is
  deleted; PVCs (prometheus/loki data) are untouched, so a resume within the 3d
  retention window keeps history.
- **No secrets touched.** The toggle only annotates/patches Applications and
  scales replicas. No Vault reads, no credential handling.
- **Scoped to dedicated namespaces.** Scaling `monitoring` + `trivy-system`
  cannot affect application workloads, which live in their own namespaces.

## Verification

1. `./scripts/k3d-manager observability_pause`
2. `kubectl --context k3d-k3d-cluster top pods -n monitoring` → pods terminating;
   `docker stats` total CPU drops by ~1.1 cores within ~60s.
3. `kubectl --context k3d-k3d-cluster -n cicd get application kube-prometheus-stack -o jsonpath='{.spec.syncPolicy.automated}'`
   → empty while paused (selfHeal suspended, so replicas stay at 0).
4. `./scripts/k3d-manager observability_resume`
5. prometheus/grafana/loki/trivy pods return within ~60s (independent of ArgoCD
   sync latency); `kubectl --context k3d-k3d-cluster -n cicd get applications`
   settles to `Synced`; Grafana history intact (PVCs never deleted).
