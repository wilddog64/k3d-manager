# Bug: one shared `observability-acg` ApplicationSet serves Hostinger and the ACG sandbox, so each sandbox lifecycle takes Hostinger's monitoring out of Argo

**Status:** OPEN — found 2026-10-23 during the tunnel bug's E2; not dispatched
**Priority:** P2
**Severity:** medium — Hostinger's Prometheus, Alertmanager, Loki and Trivy keep running, but Argo stops managing them (no sync, no drift repair, no upgrades) until the next Hostinger refresh
**Release:** v1.43.5 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-23, by Claude
**Approval:** pending — filed by Claude; dispatch needs the operator's go
**Related:** `docs/bugs/2026-10-20-acg-expiry-leaves-observability-appset-degraded.md` (its teardown fix `d26574dc` deletes this set), `docs/bugs/2026-10-23-bare-tunnel-start-repoints-hostinger-tunnel.md` (where this was seen)

**Component:** `scripts/etc/argocd/applicationsets/observability-acg.yaml`, `scripts/plugins/observability.sh` (`deploy_observability_acg`), `scripts/lib/providers/k3s-aws.sh` (sandbox deregister)

## Problem

`observability-acg` has a fixed name and a single destination, `${APP_CLUSTER_NAME}`, which
`deploy_observability_acg` fills in from whichever app cluster applies it. Its Applications
(`acg-kube-prometheus-stack`, `loki`, `acg-trivy-operator`) carry no cluster in their names.
Hostinger (`make refresh CLUSTER_PROVIDER=k3s-hostinger`) and the ACG sandbox both apply it.

So:

1. A sandbox `make up` re-applies the set with `APP_CLUSTER_NAME=ubuntu-k3s`. The three
   Applications move to the sandbox, and Hostinger's monitoring is no longer managed by Argo.
2. The sandbox teardown (`k3s-aws.sh:350`, from the 10-20 fix) strips the finalizers from the
   sandbox's Applications and then deletes `observability-acg` outright.
3. Only the next Hostinger refresh recreates it.

Evidence, 2026-10-23: the Hostinger refresh at 18:55 PDT printed
`applicationset.argoproj.io/observability-acg created`; the set and all three Applications have
`creationTimestamp` 2026-10-24T01:55:54Z, destination `ubuntu-hostinger`. Hostinger's monitoring
pods date from July and August, so the workloads survived (finalizers stripped), unmanaged.

The 10-20 bug's claim that the delete "can only target `observability-acg`; Hub, Hostinger … are not
selected" is wrong: `observability-acg` *is* Hostinger's set whenever Hostinger applied it last.

## Fix (direction; to be made exact before dispatch)

### F1. One set per app cluster

The set and its Applications are named per cluster, e.g. `observability-acg-${APP_CLUSTER_NAME}`
and `<app>-${APP_CLUSTER_NAME}`, so Hostinger and a sandbox never share one. Keep the
`k3dm.k3d.io/rollout-stage: app-cluster` label.

### F2. Teardown deletes only its own set

The sandbox deregister deletes `observability-acg-<sandbox context>` only, never another
cluster's set.

### F3. Migration

The existing shared set and its Applications currently target `ubuntu-hostinger`. Moving to the
new names must not prune Hostinger's monitoring: strip the finalizer from (or set
`preserveResourcesOnDeletion` on) the old set and Applications **before** deleting them, then apply
the per-cluster set. See `reference_preserveresourcesondeletion_rename_trap` and the
`reference_appset_generated_app_cleanup_ordering` lessons. `make appsets-reapply` and
`make appsets-check` must know the new names.

## Tests (outline)

- Rendering for `ubuntu-hostinger` and `ubuntu-k3s` gives two different set names and Application
  names; neither renders the bare `observability-acg`.
- The sandbox deregister, with a stub hub kubectl, deletes only `observability-acg-ubuntu-k3s` and
  never names the Hostinger set (red against `k3s-aws.sh:350` today).
- The migration step removes finalizers before any delete, in that order.

## Acceptance

```yaml
must:
  - id: M1
    text: Hostinger and each ACG sandbox get their own observability ApplicationSet and Applications, named per cluster.
  - id: M2
    text: A sandbox teardown removes only the sandbox's own observability set and Applications.
  - id: M3
    text: The migration from the shared set leaves every Hostinger monitoring workload running and ends with Hostinger's per-cluster set Synced and Healthy.
must_not:
  - id: N1
    text: A sandbox up or teardown must not change, move or delete Hostinger's observability set or Applications.
  - id: N2
    text: The migration must not prune any monitoring or trivy-system resource on Hostinger.
  - id: N3
    text: Tests must not reach the live hub, Hostinger or a sandbox.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, N1, N3]
    text: bats suites for observability.sh and k3s-aws.sh deregister green; the teardown test red on the pre-fix code.
  - id: E2
    kind: live
    proves: [M3, N2]
    text: Operator runs the migration; Claude confirms Hostinger monitoring pods kept their creation times and the per-cluster set is Synced/Healthy.
  - id: E3
    kind: live
    proves: [N1]
    text: Next sandbox up and teardown; Claude confirms Hostinger's set and Applications are unchanged before and after.
interface:
  - scripts/etc/argocd/applicationsets/observability-acg.yaml (envsubst APP_CLUSTER_NAME)
  - deploy_observability_acg [context]
  - k3s-aws sandbox deregister (bin/cluster-down)
  - make appsets-reapply / make appsets-check
```

## What NOT to Do

- Do NOT delete or rename the live set by hand before the migration step exists.
- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
