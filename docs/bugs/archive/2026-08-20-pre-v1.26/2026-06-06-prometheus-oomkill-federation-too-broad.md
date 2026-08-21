# Bug: Prometheus OOMKilled — federate-acg match[] too broad, memory limit too low

**Branch:** `k3d-manager-v1.6.3`
**Files:** `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`

---

## Problem

`prometheus-kube-prometheus-stack-prometheus-0` is in `CrashLoopBackOff` with exit code
137 (OOMKilled). The pod has a 1Gi memory limit. The `federate-acg` scrape job uses
`match[]: '{job!=""}'` which federates ALL metrics from ALL jobs on the ACG cluster
every 30s — thousands of time series. This causes TSDB to grow unbounded (WAL reached
125 segments) until the 1Gi limit is hit.

**Root cause:** Two compounding issues in
`scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`:
1. `federate-acg` `match[]` is `{job!=""}` — pulls every metric from every job
2. Prometheus memory limit is 1Gi with no `retentionSize` cap

---

## Fix

### Change 1 — raise memory limit to 2Gi and add retentionSize

**Exact old block (lines 12–18):**

```yaml
    resources:
      requests:
        memory: 512Mi
        cpu: 100m
      limits:
        memory: 1Gi
        cpu: 500m
```

**Exact new block:**

```yaml
    retentionSize: 1800MB
    resources:
      requests:
        memory: 512Mi
        cpu: 100m
      limits:
        memory: 2Gi
        cpu: 500m
```

### Change 2 — narrow federate-acg match[] to node and pod metrics only

**Exact old block (lines 34–36):**

```yaml
        params:
          match[]:
            - '{job!=""}'
```

**Exact new block:**

```yaml
        params:
          match[]:
            - '{job=~"node-exporter|kubelet|kube-state-metrics|istiod|envoy"}'
```

This keeps the meaningful infrastructure metrics while excluding high-cardinality
application metrics (shopping-cart app counters, histograms) that already exist in
the hub Prometheus via ArgoCD service monitors.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml` | Raise memory limit 1Gi→2Gi; add `retentionSize: 1800MB`; narrow federation match |

---

## Rules

- No other files touched
- ArgoCD will auto-sync the change once committed (selfHeal: true)

---

## Definition of Done

- [ ] `retentionSize: 1800MB` added under `prometheusSpec`
- [ ] Memory limit changed from `1Gi` to `2Gi`
- [ ] `match[]` narrowed to node/pod/istio metrics only
- [ ] Committed and pushed to `k3d-manager-v1.6.3`
- [ ] Prometheus pod restarts and stays Running (no OOMKill)
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(observability): raise prometheus memory limit to 2Gi and narrow federate-acg match to prevent OOMKill
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the listed target
- Do NOT commit to `main` — work on `k3d-manager-v1.6.3`
