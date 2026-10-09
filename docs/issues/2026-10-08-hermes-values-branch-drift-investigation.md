# Hermes values_branch drift investigation — 2026-10-08

**Result:** two live app references confirmed on v1.41.0; full screenshot count not enumerated.
**Source revision:** `84efb926ca3ad54a772572d8fee64ce1a7e8c7b0`

## Screenshot

values_branch: "15 apps not on k3d-manager-v1.42.0", examples hub-platform-ops at
k3d-manager-v1.41.0 and hub-vectordb at the previous branch; status degraded, namespace cicd.

## How the warning is produced

scripts/lib/hermes/sensors.py:values_branch obtains the expected branch from an explicit
argument, then K3DM_RELEASE_BRANCH, otherwise Hermes's git checkout branch.
It reads ArgoCD app list JSON and compares each k3d-manager source targetRevision, excluding
intentional HEAD references. Consecutive findings debounce into degraded; this state belongs
to the sensor and is separate from ArgoCD Application health/sync.

ApplicationSets render ${K3D_MANAGER_BRANCH} into targetRevision at apply time. Pulling the
laptop checkout does not mutate those live objects. The platform-ops and vectordb templates
both use that substitution. An app can be Synced to v1.41.0 while Hermes expects v1.42.0.

Whether to repin depends on the intended deployed baseline: if v1.41.0 remains intentional
during v1.42.0 development, set/validate the monitoring expectation rather than blindly
deploying unreleased config. The source mechanism permits a checkout-driven expectation;
the host environment choice was not read.

## Live read-only evidence

### hub-platform-ops

Diagnostic request `20261008T165416Z-diagnose-hub-platform-ops`, job `d6bfca01`; status request `20261008T165601Z-status-d6bfca01`.
HTTP 200, body.status=success, classification=passed.
body.exit_code is absent; do not infer one. Returned output is clipped by the bridge and begins
inside kubectl describe status/history. The live Sync Compared To section retains the target branch.

```text
ry:
            Include:        app-cluster-kubeconfig-externalsecret.yaml
          Path:             scripts/etc/argocd/platform-ops
          Repo URL:         https://github.com/wilddog64/k3d-manager
          Target Revision:  k3d-manager-v1.41.0
        Sync Options:
          CreateNamespace=true
          ServerSideApply=true
    Phase:       Succeeded
    Started At:  2026-10-03T15:59:16Z
    Sync Result:
      Resources:
        Group:       external-secrets.io
        Hook Phase:  Running
        Kind:        ExternalSecret
        Message:     externalsecret.external-secrets.io/app-cluster-kubeconfig serverside-applied
        Name:        app-cluster-kubeconfig
        Namespace:   platform-ops
        Status:      Synced
        Sync Phase:  Sync
        Version:     v1
      Revision:      cf09afcfde60931d225c6b0b28f2e82eb08f6593
      Source:
        Directory:
          Include:         app-cluster-kubeconfig-externalsecret.yaml
        Path:              scripts/etc/argocd/platform-ops
        Repo URL:          https://github.com/wilddog64/k3d-manager
        Target Revision:   k3d-manager-v1.41.0
  Reconciled At:           2026-10-08T16:49:57Z
  Resource Health Source:  appTree
  Resources:
    Group:      external-secrets.io
    Kind:       ExternalSecret
    Name:       app-cluster-kubeconfig
    Namespace:  platform-ops
    Status:     Synced
    Version:    v1
  Source Hydrator:
  Source Type:  Directory
  Summary:
  Sync:
    Compared To:
      Destination:
        Namespace:  platform-ops
        Server:     https://kubernetes.default.svc
      Source:
        Directory:
          Include:        app-cluster-kubeconfig-externalsecret.yaml
        Path:             scripts/etc/argocd/platform-ops
        Repo URL:         https://github.com/wilddog64/k3d-manager
        Target Revision:  k3d-manager-v1.41.0
    Revision:             3714a338fba31d6f6ed75133d74aa51ab829d2c2
    Status:               Synced
Events:                   <none>```
```

### hub-vectordb

Diagnostic request `20261008T165416Z-diagnose-hub-vectordb`, job `76b9f911`; status request `20261008T165601Z-status-76b9f911`.
HTTP 200, body.status=success, classification=passed.
body.exit_code is absent; do not infer one. Returned output is clipped by the bridge and begins
inside kubectl describe status/history. The live Sync Compared To section retains the target branch.

```text
Revision:  k3d-manager-v1.41.0
        Sync Options:
          CreateNamespace=true
          ServerSideApply=true
    Phase:       Succeeded
    Started At:  2026-10-03T15:59:17Z
    Sync Result:
      Resources:
        Group:       external-secrets.io
        Hook Phase:  Running
        Kind:        ExternalSecret
        Message:     externalsecret.external-secrets.io/vectordb-postgres serverside-applied
        Name:        vectordb-postgres
        Namespace:   vectordb
        Status:      Synced
        Sync Phase:  Sync
        Version:     v1
      Revision:      cf09afcfde60931d225c6b0b28f2e82eb08f6593
      Source:
        Path:              scripts/etc/argocd/vectordb
        Repo URL:          https://github.com/wilddog64/k3d-manager
        Target Revision:   k3d-manager-v1.41.0
  Reconciled At:           2026-10-08T16:49:54Z
  Resource Health Source:  appTree
  Resources:
    Kind:       PersistentVolumeClaim
    Name:       vectordb-data
    Namespace:  vectordb
    Status:     Synced
    Version:    v1
    Kind:       Service
    Name:       vectordb
    Namespace:  vectordb
    Status:     Synced
    Version:    v1
    Group:      apps
    Kind:       StatefulSet
    Name:       vectordb
    Namespace:  vectordb
    Status:     Synced
    Version:    v1
    Group:      external-secrets.io
    Kind:       ExternalSecret
    Name:       vectordb-postgres
    Namespace:  vectordb
    Status:     Synced
    Version:    v1
  Source Hydrator:
  Source Type:  Directory
  Summary:
    Images:
      pgvector/pgvector:pg17
  Sync:
    Compared To:
      Destination:
        Namespace:  vectordb
        Server:     https://kubernetes.default.svc
      Source:
        Path:             scripts/etc/argocd/vectordb
        Repo URL:         https://github.com/wilddog64/k3d-manager
        Target Revision:  k3d-manager-v1.41.0
    Revision:             3714a338fba31d6f6ed75133d74aa51ab829d2c2
    Status:               Synced
Events:                   <none>```
```

Both describe jobs succeeded. Both compared-to target revisions are k3d-manager-v1.41.0 and
both Sync statuses are Synced. These clipped logs do not establish runtime health or the full
current spec. No independent enumeration of all 15 stale references or snapshot age was obtained.
No live ApplicationSet reapply, sync, cleanup, restart or expectation change was performed.

## Confirmed wording defect

The sensor counts stale source references, not distinct apps. Multi-source apps can contribute
more than one entry; only three examples are shown. Exact unique-app count is unknown.
Filed [count wording bug](../bugs/2026-10-08-hermes-values-branch-counts-sources-as-apps.md).

Actual isolated reproduction:

```text
Fixture contains 1 application with 2 stale k3d-manager sources
Sensor message: 2 apps not on k3d-manager-v1.42.0: one-app@k3d-manager-v1.41.0, one-app@k3d-manager-v1.41.0
Confirmed: reported count is source references, not unique applications
```

## Follow-up

Read-only verification from the intended checkout:

```bash
./scripts/k3d-manager argocd_check_values_branch k3d-manager-v1.42.0 k3d-k3d-cluster
```

If v1.42.0 is the intended deployed baseline, review the rendered reapply first:

```bash
K3D_MANAGER_BRANCH=k3d-manager-v1.42.0 ./scripts/k3d-manager deploy_argocd_applicationsets --dry-run
```

The existing repair path uses deploy_argocd_applicationsets --confirm with the desired branch;
it is a live configuration change potentially triggering auto-sync/prune, and was not executed
by this investigation. Apply only after baseline/scope review, then recheck pins and app health.
A branch mismatch can explain committed config not reaching the cluster; it does not by itself
prove the prior two dashboards' No data cause.

Documentation-only filing with an isolated sensor probe. BATS/ShellCheck runtime suites do not
apply to changed Markdown; doc links and pre-commit audit check the filing.
