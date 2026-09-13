# Bug: istiod HPA churns 1→5→1 replicas on the hub

**Branch:** `k3d-manager-v1.33.0`
**Files:** `scripts/etc/argocd/applicationsets/istio-ambient.yaml`, `CHANGELOG.md`
**Status:** FIXED in git — live ApplicationSet reapply pending user go

## Problem

The hub istiod (`k3d-k3d-cluster`, chart `istiod-1.24.2`) is not crashing; its HPA scales it
up and down all day. Measured 2026-09-13:

- HPA: chart defaults `min 1 / max 5 / cpu 80%`, no `behavior`.
- Request: `cpu: 50m` (set in `2026-07-19-istio-ambient-istiod-ztunnel-cpu-rightsize.md` so istiod fits the 2-CPU hostinger node, which has ~265m unrequested CPU).
- Hub steady-state istiod usage is ~40–50m total, about the request of one pod. xDS pushes during ArgoCD syncs push one pod over 80%.
- Events over 2d: `New size: 5` ×8, `New size: 1` ×8, `4`, `3`, `2` repeatedly.
- Cluster nodes use ≤10% CPU, so this is scaling noise, not pressure. Each scale-down re-balances ztunnel xDS connections.

## Fix

Keep the 50m request (hostinger budget). Bound the HPA and damp it through `pilot` values the chart already exposes (`autoscaleMin`, `autoscaleMax`, `autoscaleBehavior` → `templates/autoscale.yaml`):

```yaml
              pilot:
                autoscaleMin: 1
                autoscaleMax: 2
                autoscaleBehavior:
                  scaleUp:
                    stabilizationWindowSeconds: 120
                  scaleDown:
                    stabilizationWindowSeconds: 900
```

At ~48m total load, 2 pods average 48%, so `ceil(2 × 48 / 80) = 2`: the HPA settles at 2 instead of oscillating. Hostinger (4% at 1 pod) stays at 1; a burst to 2 needs 50m more, which fits.

Verified with `helm template` against `istiod-1.24.2`: the HPA renders `maxReplicas: 2`, `minReplicas: 1`, and the `behavior` block.

## Live rollout (operator, needs user go)

The values are inline in the ApplicationSet, so the hub must re-read the file:

```
APP_CLUSTER_NAME=ubuntu-k3s ARGOCD_CONTEXT=k3d-k3d-cluster ./scripts/k3d-manager deploy_istio_ambient --confirm
```

The hub cluster Secret carries `k3d-manager/provider=k3d`, so the CNI dirs render identical to the live values; the only diff is the istiod HPA.

Verify: `kubectl --context k3d-k3d-cluster -n istio-system get hpa istiod` shows `MAXPODS 2`; `istiod-ubuntu-k3s` Synced/Healthy; no `SuccessfulRescale` beyond 2 over the next hour.
