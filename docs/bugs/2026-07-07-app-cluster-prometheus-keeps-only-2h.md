# Bug: App-cluster Prometheus keeps only 2h

**Filed:** 2026-07-06 (observation) / 2026-07-07 (fix spec)
**Source:** /ask agent observation, verified live on `ubuntu-hostinger`
**Branch:** `k3d-manager-v1.14.0`
**Files:** `scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml`

## Description

`scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml` sets app-cluster Prometheus `retention: 2h`, so Hostinger/app-cluster Grafana will show empty panels for older ranges even when the stack is healthy.

## Root cause (verified 2026-07-07)

Two coupled defects, not one:

1. **`retention: 2h`** (`kube-prometheus-stack-acg-values.yaml:62`) — the app-cluster Prometheus only keeps 2 hours of TSDB. Any Grafana range older than 2h renders empty.
2. **No `storageSpec`** — the `prometheusSpec` block has no `storageSpec.volumeClaimTemplate`, so the TSDB lives on the pod's default **emptyDir**. Live confirmation:

   ```
   $ kubectl --context ubuntu-hostinger -n monitoring get prometheus \
       -o jsonpath='{.items[*].spec.storage}'
   (empty)
   ```

   This is the same defect tracked in `docs/bugs/2026-07-06-prometheus-tsdb-on-emptydir.md`. It matters here because **raising `retention` alone is unsafe**: on emptyDir a longer retention just grows ephemeral node disk, and every pod restart still wipes history. The two must be fixed together.

The hub cluster already does this correctly — `kube-prometheus-stack-values.yaml:9-24` pairs `retention: 7d` + `retentionSize: 20GB` with a 25Gi `storageSpec` PVC. This spec mirrors that pattern for the app cluster (sized smaller — workloads-only).

`ubuntu-hostinger` has a default StorageClass (`local-path`, `rancher.io/local-path`), so a PVC provisions without naming a class.

## Reproduction

```bash
kubectl --context ubuntu-hostinger -n monitoring get prometheus \
  -o jsonpath='{.items[*].spec.retention}{"\n"}'
# -> 2h
# Open app-cluster Grafana, set any panel to "Last 24 hours" -> empty for t < now-2h.
# Delete the Prometheus pod -> all history gone (emptyDir).
```

## Fix

### Change 1 — `kube-prometheus-stack-acg-values.yaml`: add persistent storage + real retention

**Exact old block (lines 59-62):**

```yaml
prometheus:
  prometheusSpec:
    externalLabels:
      cluster: ubuntu-k3s
    retention: 2h
```

**Exact new block:**

```yaml
prometheus:
  prometheusSpec:
    externalLabels:
      cluster: ubuntu-k3s
    retention: 15d
    retentionSize: 8GB
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
```

> Note: the `cluster: ubuntu-k3s` external label is itself stale post-Hostinger — tracked separately in `2026-07-07-stale-kube-context-assumptions.md`. Leave it untouched here to keep this change storage-only.

`retentionSize: 8GB` caps the TSDB below the 10Gi PVC so the volume cannot fill; `retention: 15d` is the time bound. Operators can tune both once real ingest volume is known.

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml` | `retention: 2h` → `15d` + `retentionSize: 8GB` + `storageSpec` 10Gi PVC |

## Rules

- No other files touched.
- Do not remove the `cluster: ubuntu-k3s` external label in this change (separate bug).

## Definition of Done

- [ ] `kube-prometheus-stack-acg-values.yaml` has `retention: 15d`, `retentionSize: 8GB`, and a `storageSpec` PVC
- [ ] `helm template`/lint of the values file parses (no YAML indentation error)
- [ ] After redeploy: `kubectl --context ubuntu-hostinger -n monitoring get prometheus -o jsonpath='{.items[*].spec.storage}'` is non-empty and a bound PVC exists
- [ ] App-cluster Grafana renders a >2h range
- [ ] Committed and pushed to `k3d-manager-v1.14.0`
- [ ] memory-bank updated with commit SHA

**Commit message (exact):**
```
fix(observability): give app-cluster Prometheus a PVC and 15d retention
```

## What NOT to Do

- Do NOT raise `retention` without adding the `storageSpec` — that is the unsafe half-fix.
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT commit to `main` — work on `k3d-manager-v1.14.0`
