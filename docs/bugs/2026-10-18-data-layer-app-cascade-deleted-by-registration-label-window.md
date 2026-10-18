# Bug: a Hostinger re-registration made `data-git` delete the data-layer Application with a cascade finalizer

**Filed:** 2026-10-18 (Claude, found while syncing the MinIO hook fix)
**Status:** FIXED — awaiting `make appsets-reapply` + E3 live check
**Priority:** P1 — the stuck cascade deletion retries every ~16s against 43 data-layer objects (Postgres, MinIO, RabbitMQ, Redis); the only reason Hostinger's data layer still exists is that the deletes have not landed
**Severity:** high
**Approval:** approved — operator, 2026-10-18: "can you dispath those two to codex?"
**Branch:** `k3d-manager-v1.43.5`
**Release:** v1.43.5
**Component:** `scripts/etc/argocd/applicationsets/data-git.yaml`, `scripts/plugins/argocd.sh` (`register_app_cluster`)
**Fix commit:** `781494e6`

## Symptom

- `argocd app sync ubuntu-hostinger-data-layer` (2026-10-18 15:07 PDT): `FailedPrecondition desc = application is deleting`.
- Hub Application `cicd/ubuntu-hostinger-data-layer`: `deletionTimestamp=2026-10-17T23:46:39Z`,
  finalizer `resources-finalizer.argocd.argoproj.io`, condition `DeletionError` (2026-10-17T23:48:37Z).
- application-controller, every ~16s through 2026-10-18 22:08Z: `Deleting resources` /
  `43 objects remaining for deletion` for this app. No object in `shopping-cart-data` on Hostinger
  carries a deletionTimestamp yet; all 7 data pods are Running.

## Root cause

Established from the hub's ApplicationSet controller log (read-only, 2026-10-18):

```
2026-10-17T23:46:38Z processing event for cluster secret name=cluster-ubuntu-hostinger type=createSecretEventHandler
2026-10-17T23:46:38Z generated 0 applications applicationset=cicd/data-git
2026-10-17T23:46:38Z generated 0 applications applicationset=cicd/platform-helm
2026-10-17T23:46:40Z Deleted application application=ubuntu-hostinger-data-layer applicationset=cicd/data-git
2026-10-17T23:46:40Z Deleted application application=ubuntu-hostinger-shopping-cart-payment applicationset=cicd/services-git
```

The service, platform and istio Applications were recreated at 23:49:21–23:49:42Z. The data-layer
Application was not, because it is still deleting.

1. **Trigger — a label window on the cluster secret.** A write to `cluster-ubuntu-hostinger` left it
   briefly not matching `k3d-manager/role: app-cluster` + `k3d-manager/shopping-cart: "true"`, so every
   app-cluster generator returned 0 and the sets deleted their Applications. `register_app_cluster`
   (`scripts/plugins/argocd.sh`) renders the secret **without** `k3d-manager/role`, `kubectl apply`s it,
   and only afterwards calls `_argocd_set_active_app_cluster`, which adds the role with `kubectl label`.
   When an earlier apply recorded the role in `last-applied-configuration`, the new apply removes it,
   and the generators fire inside that window. Not established: which command ran at 16:46 PDT
   on 10-17 (the timing matches the Hostinger reboot recovery). The fix closes the window whichever
   caller it was.
2. **Why only the data layer is at risk.** `services-git.yaml` sets
   `spec.syncPolicy.preserveResourcesOnDeletion: true`, so its deleted Applications dropped their
   finalizer, left the workloads alone and were regenerated. `data-git.yaml` has no such setting, so
   its Application kept the cascade finalizer and ArgoCD began deleting the stateful data layer.

## Fix

- **F1.** `scripts/etc/argocd/applicationsets/data-git.yaml`: add under `spec`, between
  `goTemplateOptions` and `template`, exactly as in `services-git.yaml`:
  ```yaml
    syncPolicy:
      preserveResourcesOnDeletion: true
  ```
- **F2.** `register_app_cluster` (`scripts/plugins/argocd.sh`): before rendering, read the existing
  secret's `k3d-manager/role` label (`_kubectl get secret "${ARGOCD_APP_CLUSTER_SECRET_NAME}" -n
  "${ARGOCD_NAMESPACE}" -o jsonpath=…`, tolerating NotFound). When it is `app-cluster`, render
  `k3d-manager/role: "app-cluster"` in the same `labels:` block, so the apply never removes it. Keep
  the existing `_argocd_set_active_app_cluster` call afterwards (it still handles first-time
  registration and the exclusive mode).

### Operator recovery (not part of the fix, not Codex)

Remove the stuck finalizer so the deletion completes without cascading and `data-git` regenerates the
Application: `kubectl --context k3d-k3d-cluster -n cicd patch application ubuntu-hostinger-data-layer --type json -p '[{"op":"remove","path":"/metadata/finalizers"}]'`.
After F1 merges, run `make appsets-reapply` from the release branch so the hub's `data-git` carries it.

## Acceptance

```yaml
must:
  - id: M1
    text: The data-git ApplicationSet sets spec.syncPolicy.preserveResourcesOnDeletion to true.
  - id: M2
    text: When the existing cluster secret carries k3d-manager/role=app-cluster, the manifest register_app_cluster applies carries that label too.
  - id: M3
    text: A first-time registration (no existing secret) still ends with k3d-manager/role=app-cluster on the secret.
must_not:
  - id: N1
    text: A data-git-generated Application must not be removable with a cascade of its resources (red on pre-fix, which lacks preserveResourcesOnDeletion).
  - id: N2
    text: Re-registering an app-cluster must not apply a manifest that omits a role label the secret already has (red on pre-fix).
  - id: N3
    text: The fix must not change the data-git generator selector, template name, destination or sync options.
evidence:
  - id: E1
    proves: [M1, N1, N3]
    kind: offline
    text: a test parsing data-git.yaml (and services-git.yaml) asserting preserveResourcesOnDeletion true and the selector/template unchanged; red on the pre-fix file.
  - id: E2
    proves: [M2, M3, N2]
    kind: offline
    text: a BATS test with a stubbed _kubectl that captures the applied manifest; existing-role case red on pre-fix.
  - id: E3
    proves: [M1, N1]
    kind: live
    text: after appsets-reapply, the hub's data-git shows preserveResourcesOnDeletion true and ubuntu-hostinger-data-layer is Synced with no deletionTimestamp (Claude, read-only).
interface:
  - scripts/etc/argocd/applicationsets/data-git.yaml
  - register_app_cluster (scripts/plugins/argocd.sh), with _kubectl stubbed
```

## Definition of Done

- [ ] F1 and F2 only; tests in `scripts/tests/plugins/argocd.bats` or a new
      `scripts/tests/plugins/argocd_register_role_label.bats`.
- [ ] N1 and N2 shown red against the pre-fix source.
- [ ] `docs/guides/` page covering ApplicationSets notes that `data-git` preserves resources on deletion.
- [ ] Commit: `fix(argocd): keep data-layer resources and the role label across re-registration`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`.
- Do NOT run kubectl against any cluster; do NOT patch or sync the live Application.
- Do NOT edit `scripts/lib/foundation/`.

## Recovery and verification log

- 2026-10-18 15:14 PDT: operator removed the stuck finalizer. `data-git` recreated the Application
  at 22:14:27Z; it synced `83e8880d` and is Synced/Healthy. All 7 data pods kept running (no
  restarts) and all 7 PVCs stayed Bound (88d). The recreated Application carries
  `resources-finalizer.argocd.argoproj.io` again (not from the `data-git` template), so the exposure
  stays open until F1 is reapplied to the hub.
- 2026-10-18: Codex `781494e6`; Claude verified the diff, `argocd_register_role_label.bats` 3/3 and the
  suite set 55/55 green, and the new tests red against `bb53fd99`. The jsonpath
  `{.metadata.labels.k3d-manager/role}` reads `app-cluster` from the live hub secret.
