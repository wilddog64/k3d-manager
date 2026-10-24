# Bug: one shared `observability-acg` ApplicationSet serves Hostinger and the ACG sandbox, so each sandbox lifecycle takes Hostinger's monitoring out of Argo

**Status:** OPEN — dispatch after `2026-10-23-api-cluster-status-posts-to-command-channel` lands
**Priority:** P2
**Severity:** medium — Hostinger's Prometheus, Alertmanager, Loki and Trivy keep running, but Argo stops managing them (no sync, no drift repair, no upgrades) until the next Hostinger refresh
**Release:** v1.43.5 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-23, by Claude
**Approval:** explicit 2026-10-23. The operator said: "yes, go ahead" (write the exact spec, dispatch after the status-channel fix).
**Related:** `docs/bugs/2026-10-20-acg-expiry-leaves-observability-appset-degraded.md` (its teardown fix `d26574dc` deletes this set), `docs/bugs/2026-10-23-bare-tunnel-start-repoints-hostinger-tunnel.md` (where this was seen)

**Component:** `scripts/etc/argocd/applicationsets/observability-acg.yaml`, `scripts/plugins/observability.sh` (`deploy_observability_acg`), `scripts/plugins/argocd.sh` (`_argocd_deploy_applicationsets`), `scripts/lib/providers/k3s-aws.sh` (`_k3s_aws_deregister_cluster`)

## Problem

`observability-acg` has a fixed name and a single destination, `name: ${APP_CLUSTER_NAME}`, which
`deploy_observability_acg` fills in from whichever app cluster applies it. Its Applications
(`acg-kube-prometheus-stack`, `loki`, `acg-trivy-operator`) carry no cluster in their names. Both
Hostinger (`make refresh CLUSTER_PROVIDER=k3s-hostinger`) and the ACG sandbox (`make up`) apply it.

1. A sandbox `make up` re-applies the set with `APP_CLUSTER_NAME=ubuntu-k3s`. The three
   Applications move to the sandbox, and Hostinger's monitoring is no longer managed by Argo.
2. The sandbox teardown (`_k3s_aws_deregister_cluster`, `k3s-aws.sh:350`, from the 10-20 fix)
   strips the sandbox's Applications' finalizers, then deletes `observability-acg` outright.
3. Only the next Hostinger refresh recreates it, and that refresh in turn takes it from any
   running sandbox.

Evidence, 2026-10-23: the Hostinger refresh at 18:55 PDT printed
`applicationset.argoproj.io/observability-acg created`; the set and its three Applications have
`creationTimestamp` 2026-10-24T01:55:54Z, destination `ubuntu-hostinger`. Hostinger's monitoring
pods date from July and August: the workloads survived, unmanaged.

The 10-20 bug's claim that the delete "can only target `observability-acg`; Hub, Hostinger … are not
selected" is wrong: `observability-acg` *is* Hostinger's set whenever Hostinger applied it last.

Live facts that constrain the fix (read 2026-10-23):

- The three Applications carry `resources-finalizer.argocd.argoproj.io`. If the set stops
  generating them while the finalizer is on, Argo **prunes Hostinger's monitoring stack**.
- No `helm.releaseName` is set, so each Helm release is named after its Application
  (`acg-kube-prometheus-stack`, …). Workload selectors use it
  (e.g. operator Deployment `release: acg-kube-prometheus-stack`), and selectors are immutable.
- Cluster registrations: `cluster-ubuntu-hostinger` has `k3d-manager/role: app-cluster`,
  `k3d-manager/provider: k3s-hostinger`. The hub's own registration (`ubuntu-k3s-app-cluster`,
  cluster `k3d-cluster`) also has `role: app-cluster`, with `provider: k3d`. The sandbox is
  registered by `bin/cluster-up` with `ARGOCD_APP_CLUSTER_PROVIDER` = the cluster provider
  (confirm it is `k3s-aws` from the code, and test it).
- `_argocd_appset_live_overrides` keeps a live set's `${APP_CLUSTER_NAME}` destination on
  `make appsets-reapply`.

## Fix

### F1. One set, one Application per app cluster (matrix generator)

Rewrite `observability-acg.yaml` (keep its name, labels and `k3dm.k3d.io/rollout-stage: app-cluster`)
as a matrix of:

- a `clusters` generator selecting `k3d-manager/role: app-cluster` **and**
  `k3d-manager/provider In (k3s-hostinger, k3s-aws)`, so the hub (`k3d`) is never selected;
- the existing list generator, with the element key `name` renamed to `app` (it would collide
  with the cluster generator's `name`).

Template:

- `metadata.name: '{{.name}}-{{.app}}'` (e.g. `ubuntu-hostinger-acg-kube-prometheus-stack`).
- `destination.name: '{{.name}}'`.
- Helm `releaseName: '{{.app}}'` on the chart source, so release names, resource names and
  selectors stay exactly as they are today.
- `clusterLabel` (the `prometheus.prometheusSpec.externalLabels.cluster` parameter) becomes
  `'{{.name}}'`; drop the `clusterLabel` list key.
- `spec.syncPolicy.preserveResourcesOnDeletion: true` on the ApplicationSet, so an Application
  the set stops generating (a cluster deregistered, or the rename below) never prunes workloads.
- No `${APP_CLUSTER_NAME}` anywhere in the file. `goTemplateOptions: [missingkey=error]` as in
  `grafana-dashboards-acg.yaml`.

### F2. Retire the legacy Applications before the new template is applied

New helper in `scripts/plugins/argocd.sh`, `_argocd_retire_legacy_observability_acg_apps`. For each
of `acg-kube-prometheus-stack`, `loki`, `acg-trivy-operator` in `${ARGOCD_NAMESPACE:-cicd}` that
exists and is owned by ApplicationSet `observability-acg`, in this order:

1. patch the live set (if it exists) with `spec.syncPolicy.preserveResourcesOnDeletion: true`;
2. remove the Application's finalizers (`{"metadata":{"finalizers":null}}`);
3. only then let the new template be applied (the set deletes the legacy Applications without
   pruning; the new per-cluster Applications adopt the same resources by release name).

Step 2 failing for any Application aborts the apply with an error: never apply the new template
while a legacy Application still has its finalizer. The helper is a no-op when none exist.

Call it immediately before `observability-acg.yaml` is applied, on **both** paths:

- `deploy_observability_acg` (Hostinger refresh, sandbox up);
- `_argocd_deploy_applicationsets` (`make appsets-reapply`), for that file only.

`observability.sh` must load `argocd.sh` if the helper is not defined (as
`_k3s_aws_deregister_cluster` does), and fail, not skip, if it still cannot.

### F3. `deploy_observability_acg`

Stop substituting `APP_CLUSTER_NAME` into the set (keep `ARGOCD_NAMESPACE` and
`K3D_MANAGER_BRANCH`). It still resolves `_app_context` for its own later steps (Pushgateway,
Promtail, PrometheusRule wait) and the log line. The app cluster must already be registered for the
set to generate its Applications; it already is on both paths (registration runs first).

### F4. Teardown deletes only the sandbox's Applications

In `_k3s_aws_deregister_cluster`, remove the `delete applicationset observability-acg` and fix the
`_info` message to match. The existing loop (strip finalizers, delete Applications whose
destination is the sandbox) stays. Deleting the registration Secret makes the set stop generating
the sandbox's Applications, and `preserveResourcesOnDeletion` keeps that from pruning a dead
cluster.

### F5. Docs

`docs/guides/grafana-dashboards/shared-operations.md` (or the observability section that names
`observability-acg`): one Application per app cluster, named `<cluster>-<app>`; the hub is
excluded; teardown leaves other clusters alone. Fix the 10-20 bug doc's "Hostinger is not selected"
sentence with a one-line correction pointing here.

## Tests

`scripts/tests/plugins/argocd_appset_live_overrides.bats`, `scripts/tests/lib/observability.bats`,
`scripts/tests/lib/k3s_aws_deregister.bats` (stub hub `kubectl`, record calls; never the live hub):

1. The rendered set has a matrix generator; its cluster selector requires `role: app-cluster` and
   provider in `k3s-hostinger`, `k3s-aws`; the template name is `{{.name}}-{{.app}}`, the
   destination `{{.name}}`, `releaseName` `{{.app}}`; `preserveResourcesOnDeletion: true`; no
   `${APP_CLUSTER_NAME}` (assert on these tokens, not on whole lines).
2. `_k3s_aws_deregister_cluster` never deletes an ApplicationSet (red today).
3. `deploy_observability_acg` with three legacy Applications owned by `observability-acg`: the
   recorded calls are the set patch, then three finalizer removals, then the apply, in that order
   (red today).
4. A finalizer removal that fails: the apply is never called and the function returns non-zero.
5. No legacy Applications: no patch or finalizer call; the apply runs.
6. The `make appsets-reapply` path (`_argocd_deploy_applicationsets`) runs the same retirement
   before applying `observability-acg.yaml`, and only for that file (red today).
7. `bin/cluster-up` registers the sandbox with `k3d-manager/provider: k3s-aws` (or whatever the
   code sets; the selector in test 1 must match it).

Show tests 2, 3 and 6 red against the pre-fix code on a temp copy.

## Files

- `scripts/etc/argocd/applicationsets/observability-acg.yaml`
- `scripts/plugins/observability.sh`
- `scripts/plugins/argocd.sh`
- `scripts/lib/providers/k3s-aws.sh`
- `scripts/tests/plugins/argocd_appset_live_overrides.bats`
- `scripts/tests/lib/observability.bats`
- `scripts/tests/lib/k3s_aws_deregister.bats`
- `scripts/tests/bin/cluster_up.bats` (test 7 only)
- `docs/guides/grafana-dashboards/shared-operations.md`
- `docs/bugs/2026-10-20-acg-expiry-leaves-observability-appset-degraded.md` (one-line correction)
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: Every registered Hostinger or ACG sandbox app cluster gets its own observability Applications, named <cluster>-<app>, from the one observability-acg set; the hub gets none.
  - id: M2
    text: Helm release names, and so workload names and selectors, are unchanged from today.
  - id: M3
    text: Moving from the legacy Applications retires them without pruning, on the deploy path and on make appsets-reapply.
  - id: M4
    text: A sandbox teardown removes only the sandbox's observability Applications and leaves the set and Hostinger's Applications in place.
must_not:
  - id: N1
    text: A sandbox up or teardown must not change, move or delete Hostinger's observability Applications.
  - id: N2
    text: The new template must never be applied while a legacy Application still has its resources finalizer.
  - id: N3
    text: The hub cluster must not be selected by observability-acg.
  - id: N4
    text: Tests must not reach the live hub, Hostinger or a sandbox.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, N1, N2, N3, N4]
    text: The four bats suites green; tests 2, 3 and 6 red on the pre-fix code.
  - id: E2
    kind: live
    proves: [M1, M2, M3, N2]
    text: Operator runs make refresh CLUSTER_PROVIDER=k3s-hostinger; Claude confirms ubuntu-hostinger-<app> Applications Synced/Healthy, the legacy three gone, and Hostinger monitoring pods kept their creation times.
  - id: E3
    kind: live
    proves: [M1, M4, N1]
    text: Next sandbox up then teardown; Claude confirms ubuntu-k3s-<app> appear then go, and Hostinger's Applications are unchanged throughout.
interface:
  - scripts/etc/argocd/applicationsets/observability-acg.yaml (rendered by deploy_observability_acg / make appsets-reapply)
  - deploy_observability_acg [context]
  - _argocd_deploy_applicationsets (make appsets-reapply)
  - _k3s_aws_deregister_cluster (bin/cluster-down)
```

## Definition of Done

- [ ] F1–F5 and a CHANGELOG `[Unreleased]` `### Fixed` entry; only the Files above change.
- [ ] The four bats suites green; paste the summaries. `shellcheck -S warning` clean on the three changed scripts.
- [ ] Tests 2, 3 and 6 shown red on a temp copy of the pre-fix code.
- [ ] Commit: `fix(observability): give each app cluster its own observability Applications`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT run `kubectl` against the hub, Hostinger or a sandbox, or run `make refresh`, `make up` or `make appsets-reapply`.
- Do NOT delete or rename the live set or Applications by hand; the migration is code, run by the operator.
- Do NOT change chart versions, values files or the `grafana-dashboards-acg` set.
- Do NOT modify files outside the Files list.
