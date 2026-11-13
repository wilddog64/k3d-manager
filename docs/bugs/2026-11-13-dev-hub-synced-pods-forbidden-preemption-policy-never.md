# dev-hub: every synced pod is forbidden — PriorityClass `preemptionPolicy: Never` conflicts with the pod spec vCluster copies

**Status:** OPEN
**Priority:** P1 (Claude proposal: no pod inside the dev hub can run, so CoreDNS, Argo CD and Grafana never start; blocks dev-hub plan E2 in the open v1.44.0 release)
**Classified:** pending (Argon, from this doc alone)
**Waiting on:** operator decision — since 2026-11-13
**Introduced by:** b2067ad3 (dev-hub Part A, `scripts/etc/dev-hub/priorityclass.yaml`)
**Should have been caught by:** live check (host admission is invisible to offline tests; the first live run stopped earlier, at the coredns schema bug)
**Prior art:** exact-slug glob, no match; `make find-similar-docs` unavailable (vector store context `k3d-k3d-cluster` missing); related, different root cause: docs/bugs/2026-11-13-dev-hub-up-fails-vcluster-rejects-top-level-coredns.md
**Approval:** pending

## Symptom

On m5-air, 2026-11-13 ~11:00 PST, vCluster 0.32.1, after the coredns fix (8c2bfc5f) let `make dev-hub-up` create the vCluster: inside the vCluster `pod/coredns-7c7ccd6944-m85br` stays Pending, there is no host copy in namespace `dev-hub`, and `make dev-hub-up` hangs at "Release "argocd" does not exist. Installing it now." The event on the virtual pod (read-only capture by the operator):

    Warning  SyncError  pod-syncer  Error syncing to host cluster: create object: pods "coredns-7c7ccd6944-m85br-x-kube-system-x-dev-hub" is forbidden: the string value of PreemptionPolicy (PreemptLowerPriority) must not be provided in pod spec; priority admission controller computed Never from the given PriorityClass name

Quota is not the cause: `dev-hub-budget` shows 1/30 pods, 256Mi/1Gi requests.memory.

## Root cause

`values-dev-hub.yaml` sets `sync.toHost.pods.priorityClassName: k3dm-dev-preemptible`. The syncer swaps the class name but keeps `spec.preemptionPolicy`, which the virtual API server already filled in (`PreemptLowerPriority`, from the virtual pod's own class). The host's Priority admission plugin works out `Never` from `k3dm-dev-preemptible` and rejects any pod whose spec already carries a different value. The control-plane pod `dev-hub-0` gets past this because the host StatefulSet creates it with no preemptionPolicy set, so admission fills it in. Every pod the syncer copies hits the error.

## Proposed fix (needs an operator decision)

Remove `preemptionPolicy: Never` from `scripts/etc/dev-hub/priorityclass.yaml`, so the default `PreemptLowerPriority` applies and matches what synced pods carry. At `value: -100` the class can preempt only pods below -100, and the hub has none, so dev-hub pods still give way to hub workloads, which is what the plan wants. Two things must be proved before dispatch, under the prove-external-behaviour rule:
- `preemptionPolicy` on a PriorityClass is likely immutable (upstream `ValidatePriorityClassUpdate`). If so, `dev_hub_up`'s `kubectl apply` fails on the live hub until the old class is deleted. The fix then needs a delete-and-recreate step, or a new class name.
- vCluster 0.32.1 has no setting that drops or rewrites the copied preemptionPolicy (check upstream source at the tag). If one exists, it is the smaller change.
