# P3: `CLUSTER_NAME` Env Var Not Respected by `deploy_cluster`

**Date:** 2026-03-01
**Reported:** Observed during infra cluster rebuild (post v0.3.0 merge)
**Status:** OPEN
**Severity:** P3
**Type:** Bug — env var override silently ignored

---

## What Happened

When running:

```bash
CLUSTER_NAME=automation CLUSTER_ROLE=infra ./scripts/k3d-manager deploy_cluster
```

The cluster was created as `k3d-cluster` instead of `automation`. The `CLUSTER_NAME=automation` env var was silently ignored.

**Observed cluster name:** `k3d-cluster`
**Expected cluster name:** `automation`

---

## Impact

- Infra cluster is running as `k3d-cluster` instead of `automation`
- `kubectl` context is `k3d-k3d-cluster` instead of `k3d-automation`
- CI `check_cluster_health.sh` may reference cluster by context name — needs to be verified
- Operationally non-blocking (cluster works), but naming is inconsistent with documented plan

---

## Root Cause (Suspected)

`CLUSTER_NAME` is likely defaulted early in the dispatcher or provider before the env var is read, or there is a hardcoded default that overrides the env var. Needs investigation in:

- `scripts/k3d-manager` (dispatcher)
- `scripts/lib/providers/orbstack.sh` or `scripts/lib/providers/k3d.sh`
- Any `CLUSTER_NAME` defaulting logic

---

## Workaround

The cluster is functional under the name `k3d-cluster`. All `kubectl` commands work normally. Deployment continues under the current name.

---

## Triage

| Factor | Assessment |
|---|---|
| Operational impact | Low — cluster works, wrong name |
| Fix urgency | P3 — nice to have before next rebuild |
| Likely fix | Find where `CLUSTER_NAME` is defaulted and ensure env var is checked first |
