# istio-ambient ApplicationSet targets the retired `ubuntu-k3s` cluster; Hostinger Istio is unmanaged

**Status:** OPEN — filed 2026-11-22
**Priority:** P2
**Introduced by:** unknown (ApplicationSet created 2026-10-30 14:18, the hub rebuild; `scripts/etc/argocd/vars.sh:68` defaults `ARGOCD_APP_CLUSTER_NAME` to `ubuntu-k3s`)
**Should have been caught by:** live check
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-22
**Prior art:** docs/issues/2026-08-13-stale-istio-ubuntu-k3s-applications.md (exact-slug pass; vector pass unavailable: no `k3d-k3d-cluster` context on M4) — read, different root cause (that was four stale Applications on a dead endpoint; the ApplicationSet then rendered `ubuntu-hostinger`)

## Symptom

Operator, 2026-11-22: the `istio-ambient` ApplicationSet in the hub ArgoCD UI has shown Degraded with 0 Applications
for 23 days.

## Evidence (Claude, read-only, M5 hub over ssh, 2026-11-22)

- `kubectl get applicationsets.argoproj.io -A -o json`, `istio-ambient` status:
  - `ErrorOccurred True ApplicationValidationError | application destination spec is invalid: there are no clusters with this name: ubuntu-k3s (and 3 more)`
  - `ParametersGenerated True`; `ResourcesUpToDate False`; `resources: None`.
- Its generator renders four elements (istio-base, istiod, istio-cni, ztunnel); the template is
  `scripts/etc/argocd/applicationsets/istio-ambient.yaml` (`destination.name: ${APP_CLUSTER_NAME}`, line 84).
- No Istio Application exists on the hub (full `applications.argoproj.io` list read the same day).
- Hostinger Istio still runs, outside ArgoCD: `kubectl --context ubuntu-hostinger -n istio-system get pods` shows
  `istiod` (89d), `ztunnel` (94d), `istio-cni-node` (44d), all Running.
- The hub kubeconfig still has an `ubuntu-k3s` context, but ArgoCD has no cluster of that name.

## Impact

- Hostinger's ambient mesh (istiod, ztunnel, istio-cni) is not reconciled: chart pins, values (HPA bounds, CNI dirs,
  resources) and self-heal no longer apply. A drift or deletion would not be corrected, and a version bump in the
  template would not reach the cluster.
- The UI shows a permanent red ApplicationSet, which hides any new ApplicationSet error.
- Workaround: the mesh keeps running as last deployed.

## Likely cause (unverified)

`ARGOCD_APP_CLUSTER_NAME` / `APP_CLUSTER_NAME` falls back to `ubuntu-k3s` (`scripts/etc/argocd/vars.sh:68`,
`bin/cluster-up:1007`, `:1068`) when the ApplicationSet was rendered on 2026-10-30 without the Hostinger name. The
other Hostinger ApplicationSets render `ubuntu-hostinger`; find which reapply path rendered this one without it.

## Not done

No change to the hub. A fix (render with `ubuntu-hostinger`, decide whether the `ubuntu-k3s` default should fail
closed instead) and the adoption of the running Istio resources by new Applications need a spec and an operator go.
