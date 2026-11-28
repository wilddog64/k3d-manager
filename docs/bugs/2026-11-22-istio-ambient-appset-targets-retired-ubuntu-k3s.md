# Stale ACG sandbox ApplicationSet `istio-ambient` (`ubuntu-k3s`) left on the hub; stale-sandbox sweep misses ArgoCD

**Status:** OPEN — filed 2026-11-22
**Priority:** P3 (operator 2026-11-22: "not hurting anything but annoy"; must be scheduled, not left in the pile)
**Introduced by:** unknown (ApplicationSet created 2026-10-30 14:18, the hub rebuild; `scripts/etc/argocd/vars.sh:68` defaults `ARGOCD_APP_CLUSTER_NAME` to `ubuntu-k3s`)
**Should have been caught by:** live check
**Introducing change reviewed:** unknown
**Waiting on:** dispatch — since 2026-11-27 (check: still present)
**Triage:** carry → v1.46.0 (operator 2026-11-22: schedule the fix)
**Re-triage:** 2026-11-27 — check first in v1.46.0 — close if already resolved, else decide (operator 2026-11-27)
**Branch:** k3d-manager-v1.46.0
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

## Operator context 2026-11-22

Operator: "ubuntu-k3s is ACG aws sandbox. this probably a stale resource that need to be cleanup. might be cause by not
running make down... we should have process to sweep these away".

So the ApplicationSet is a leftover of an ACG AWS sandbox that was not torn down with `make down`, not a Hostinger
render. Revised reading:

- Current sweep gap: `bin/cleanup-stale-sandbox` (also `/cleanup-stale-sandbox`) stops the sandbox launchd agents and
  deletes the `ubuntu-k3s` kube context only (lines 18-22). It does not touch ArgoCD: sandbox ApplicationSets,
  Applications, or cluster secrets stay on the hub. On 2026-11-22 the hub still had the `ubuntu-k3s` kube context too.
- Open question: Hostinger Istio. The 2026-08-13 issue saw the same `istio-ambient` ApplicationSet rendering
  `ubuntu-hostinger` with Synced/Healthy Hostinger Istio Applications. Today no Istio Application exists and Hostinger
  istiod/ztunnel/istio-cni run unmanaged. One ApplicationSet name serves both clusters, so a sandbox `make up` on
  10-30 may have replaced the Hostinger rendering. Confirm before deleting: deleting the ApplicationSet clears the red
  but leaves Hostinger Istio unmanaged.

## Proposed fix (for triage)

1. Sweep: extend `bin/cleanup-stale-sandbox` (dry run by default, `--confirm` applies) to list and remove hub ArgoCD
   objects that target a sandbox cluster with no live registration: ApplicationSets/Applications whose destination is
   the sandbox name, and the sandbox cluster secret. Report each one; never touch a `ubuntu-hostinger` or hub target.
2. Detection: an alert or `make hub-status` line for an ApplicationSet with `ErrorOccurred=True` for more than a day,
   so a 23-day red cannot recur unseen.
3. Collision: give sandbox and Hostinger renders distinct ApplicationSet names (e.g. `istio-ambient-${APP_CLUSTER_NAME}`),
   then restore Argo management of Hostinger Istio (adoption needs its own spec; live mesh).


## Check — 2026-11-27 (Claude, read-only, m5 hub over ssh)

Still present: `kubectl get applicationset -n cicd istio-ambient` conditions `ErrorOccurred=True` and
`ResourcesUpToDate=False` — `application destination spec is invalid: there are no clusters with this name: ubuntu-k3s
(and 3 more)`. Operator re-triage 2026-11-27: not resolved → fix in v1.46.0 (spec, Fable + Neon review, dispatch).
