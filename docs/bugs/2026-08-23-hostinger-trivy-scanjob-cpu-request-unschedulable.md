# Bugfix: hostinger Trivy scan jobs unschedulable — scan-job CPU request too large for a saturated 2-CPU node

**Branch:** `k3d-manager-v1.27.0`
**File:** `scripts/etc/helm/observability/trivy-operator-acg-values.yaml`

---

## Problem

CVE dashboard **panel ② ("Shopping-cart Unique CVEs")** is empty. The hub exporter → hostinger
wiring is complete and verified (ExternalSecret `app-cluster-kubeconfig` synced, exporter
`app_target()` succeeds, read-only SA can `list` vulnerabilityreports). The panel is empty because
**hostinger has zero `vulnerabilityreports`** — the Trivy operator cannot produce any.

Root cause: on `ubuntu-hostinger` (single node `srv1754834`, **2 CPU = 2000m allocatable**), pod CPU
**requests** already total **1960m (98%)** from legitimate workloads (payment 200m, rabbitmq 200m,
3×postgres, minio, order, basket, loki, istio, coredns, metrics-server). Only ~40m is free.

Each Trivy scan-job pod runs **one container per target-workload container**, and every scan
container carries `trivy.resources.requests.cpu: 50m`. A 2- or 3-container target → a scan pod that
reserves 100–150m, which does not fit the ~40m headroom. Result: every scan pod is
`Pending` with `FailedScheduling: 0/1 nodes are available: 1 Insufficient cpu`, so no report is ever
written. Because no report exists, there is no report-TTL to expire and trigger a rescan — the
operator sits idle and the panel stays empty indefinitely.

The node's **actual** CPU usage is only ~19% (398m/2000m); the wall is scheduling *reservations*,
not real load. This is the same 2-CPU reservation squeeze recorded in
`docs/bugs/2026-07-22-hostinger-trivy-cpu-oversubscription-502.md` (that fix trimmed the Trivy
**server** request; this one trims the scan-**job** request).

## Fix

Trim the scan-job container CPU **request** from `50m` to `10m`. Keep the CPU **limit** at `500m`
so real scans still burst — only the scheduling reservation shrinks. A 3-container scan pod then
reserves 30m and fits the existing headroom. **Do not touch memory** — trivy scan jobs OOM at low
memory (see `docs/bugs/2026-07-12-trivy-scan-jobs-oomkilled-at-512mi.md`); leave `256Mi`/`1Gi`.

**Exact old block** (`scripts/etc/helm/observability/trivy-operator-acg-values.yaml`, `trivy.resources`):

```yaml
  resources:
    requests:
      memory: 256Mi
      cpu: 50m
    limits:
      memory: 1Gi
      cpu: 500m
```

**Exact new block:**

```yaml
  resources:
    requests:
      memory: 256Mi
      cpu: 10m
    limits:
      memory: 1Gi
      cpu: 500m
```

> This is the `trivy.resources` block (scan-job containers), NOT `trivy.server.resources` and NOT
> `operator.resources`. Leave those unchanged.

## Why this file (not app-workload trims)

The alternative — trimming payment/rabbitmq requests (200m each) — lives in the shopping-cart repos
and needs cross-repo PRs. Trimming the scan-job request is fully k3d-manager-scoped, leaves
application resources intact, and matches the v1.16.0 precedent (trim request, keep limit). Chosen
over app-workload trims per the 2026-08-23 decision ("durable request trim in git").

## Making it live (release mechanics)

The `acg-trivy-operator` ArgoCD app is multi-source; its `$values` ref is frozen to whichever branch
was checked out when the observability ACG ApplicationSet was last applied (was `k3d-manager-v1.26.0`).
A commit to `k3d-manager-v1.27.0` is **inert** until that appset is reapplied at
`K3D_MANAGER_BRANCH=k3d-manager-v1.27.0` (repoints `$values` → v1.27.0, auto-sync then re-renders).
Reapply per the CLAUDE.md rule, confirm with `argocd_check_values_branch`.

## Follow-on: scans schedule but hit `DeadlineExceeded` (5m → 15m)

After the 10m request trim let scan pods schedule, every scan job then failed with
`DeadlineExceeded` (`Job was active longer than specified deadline`) at exactly 5 minutes —
`trivy.timeout: 5m0s`. In `ClientServer` mode with `trivy.slow: true` on a CPU-contended node,
client-side image analysis (layer download + extraction) for the larger workload images
(postgres, minio) does not finish inside 5m. trivy-server itself is healthy (DB downloaded,
endpoint live) — the timeout is client-side.

Fix: raise `trivy.timeout` to `15m0s`, keep `slow: true` (memory safety — do not disable it, the
scan jobs OOM without it). Added `trivy.slow`/`trivy.timeout` explicitly to the values file so both
are pinned rather than chart-defaulted.

## Definition of Done

- [ ] `trivy.resources.requests.cpu: 10m`; limits unchanged (`cpu: 500m`); memory unchanged.
- [ ] YAML parses: `python3 -c "import yaml; yaml.safe_load(open('scripts/etc/helm/observability/trivy-operator-acg-values.yaml'))" && echo OK`.
- [ ] Committed + pushed to `k3d-manager-v1.27.0`.
- [ ] Observability ACG appset reapplied at v1.27.0; `acg-trivy-operator` `$values` ref now v1.27.0.
- [ ] Live: scan pods leave `Pending`, `vulnerabilityreports` appear on hostinger, exporter emits
      `trivy_vulnerability_inventory{cluster="ubuntu-hostinger"}` series, panel ② fills.
- [ ] memory-bank updated (separate commit).
