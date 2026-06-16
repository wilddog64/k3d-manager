# vCluster preflight: production ApplicationSets leak onto the throwaway vcluster

**Date:** 2026-06-16
**Component:** `bin/cluster-preflight` (vCluster preflight, v1.1.1)
**Found by:** Claude (live diagnosis on a clean `vok` repro, `ubuntu-hostinger`)
**Severity:** blocks delete-on-success — preflight can never reach Synced/Healthy → `--auto` always keeps the cluster as a "failure"

---

## Symptom

A clean default-mode run (`bin/cluster-preflight vok`) creates + registers the vcluster and
deploys the prefixed-clone ArgoCD resources, but the 300s convergence wait always times out
(`rc=1`). The `--auto` trap then correctly keeps the cluster — but the run is a *false* failure:
the flag logic is fine, the **deploy never converges**.

Per-app state after the wait:

| App | Sync / Health | Note |
|-----|---------------|------|
| `vok-platform` | Unknown / Unknown | `InvalidSpecError` |
| `vok-preflight-data-layer` | OutOfSync / Missing | `SyncError: one or more synchronization tasks are not valid` |
| `vok-preflight-shopping-cart-{order,payment,product-catalog}` | OutOfSync / Missing/Degraded | downstream of data-layer |
| `vok-preflight-shopping-cart-{basket,frontend,namespace}` | Synced (Degraded/Healthy) | cluster IS reachable |
| `vok-preflight-acg-trivy-operator` | Synced / Healthy | clones partly work |

So the vcluster is reachable and *some* prefixed clones sync — this is not a connectivity bug.

---

## Root cause (definitive)

**The throwaway vcluster's cluster secret carries `environment: dev`, and the LIVE production
`platform-helm` ApplicationSet selects clusters by `environment` alone — so production grabs the
throwaway cluster and deploys the live platform app-of-apps onto it.**

Evidence:

1. `vok-platform` is **owned by the live `platform-helm` ApplicationSet** (not the preflight clone):
   ```
   ownerReferences: [{kind: ApplicationSet, name: platform-helm, controller: true}]
   labels: {cluster: vok, environment: dev}
   ```

2. The live `platform-helm` generator selects on `environment` only — **no cluster-name guard**:
   ```
   matchExpressions: [{key: environment, operator: In, values: [dev, infra, prod]}]
   ```

3. The preflight registers the cluster secret `cluster-vok` with `environment: dev`:
   ```
   labels: {argocd-chart-version: 7.8.1, argocd-replicas: 2,
            argocd.argoproj.io/secret-type: cluster, environment: dev}
   ```
   → the live appset's selector matches it → generates `vok-platform`.

4. `vok-platform` uses `project: platform` (the LIVE project). The live `platform` project's
   destination allow-list has **zero** entries for the vcluster server
   (`https://srv1754834.hstgr.cloud:30360`) → ArgoCD rejects it:
   ```
   InvalidSpecError: application destination server '.../:30360' and namespace 'cicd'
   do not match any of the allowed destinations in project 'platform'
   ```

5. The preflight *clone* appset `vok-preflight-platform-helm` is rendered correctly
   (`template.name: vok-preflight-platform`, `template.project: vok-preflight-platform`) but its
   generated app is **absent** — production's `vok-platform` occupies the platform app-of-apps slot
   for that cluster, and the production platform stack never installs the prerequisites
   (namespaces, ESO/CRDs) the clones depend on → cascade failures (`data-layer` SyncError,
   `shopping-cart-data` namespace never created — only `shopping-cart-apps` exists on vok).

---

## Why the existing `allow_platform_destination` is a red herring

`bin/cluster-preflight` defines `_cluster_preflight_allow_platform_destination` (patches the live
`platform` project to permit the vcluster destination) — but it is **dead code, never called**
(only its `remove` counterpart is wired into the cleanup trap). Wiring it in would make the live
`platform` project *accept* the throwaway destination, but that is the wrong remedy: it lets
production apps deploy onto the throwaway cluster. The correct fix is **isolation** — keep
production ApplicationSets from selecting the preflight cluster at all.

---

## Fix direction (for the spec → Codex)

1. **Register the preflight cluster with an `environment` value the live appsets do NOT select**
   (e.g. `environment: preflight`), so live `platform-helm` / `services-git` / `observability-acg`
   no longer match it. (Verify the live `services-git` / `observability-acg` generators too — their
   `matchExpressions` came back empty, so confirm whether they select all clusters.)
2. **Update the preflight clone appsets** to select on that label value (alongside the existing
   `cluster-name In [<name>]` guard) so the clones still target the throwaway cluster.
3. **Drop / repurpose** the dead `_cluster_preflight_allow_platform_destination` +
   `_cluster_preflight_remove_platform_destination` pair once isolation removes the need to patch
   the live `platform` project.
4. **Re-verify** namespace creation ordering (`shopping-cart-data` was missing) once the platform
   clone owns the stack.

---

## Repro

```bash
bin/cluster-preflight vok          # default --auto, clean vclusters ns
# → vcluster up, registered, clones applied, 300s wait times out → rc=1 → kept
kubectl --context k3d-k3d-cluster -n cicd get application | grep vok
kubectl --context k3d-k3d-cluster -n cicd get application vok-platform \
  -o jsonpath='{.metadata.ownerReferences}'   # → ApplicationSet/platform-helm (LIVE)
```

`vok` is kept as the triage repro (replaces `pr33`, which was torn down 2026-06-16).
