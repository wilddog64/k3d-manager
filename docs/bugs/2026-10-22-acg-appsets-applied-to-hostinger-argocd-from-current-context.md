# Bug: ACG ApplicationSets were applied to Hostinger's own ArgoCD and are stuck on v1.40.0

**Filed:** 2026-10-22 (Claude, found during GitHub branch pruning)
**Status:** OPEN
**Priority:** P3 — the stray sets generate no Applications; they only pin a release branch and log errors
**Severity:** low
**Approval:** approved — operator, 2026-10-22: "and file stale Hostinger ApplicationSets"
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Component:** `scripts/plugins/observability.sh` (`deploy_observability_acg`)
**Related:** `docs/bugs/2026-10-20-acg-expiry-leaves-observability-appset-degraded.md`

## Symptom

Hostinger runs its own ArgoCD (`argocd-ubuntu-hostinger-*` in `cicd`). On 2026-10-22 it holds two
ApplicationSets that belong on the hub:

| Context | Namespace | ApplicationSet | Created (UTC) | `$values` ref |
|---|---|---|---|---|
| `ubuntu-hostinger` | `cicd` | `grafana-dashboards-acg` | 2026-09-29 22:37 | `k3d-manager-v1.40.0` |
| `ubuntu-hostinger` | `cicd` | `observability-acg` | 2026-09-29 22:37 | `k3d-manager-v1.40.0` |

- Neither generates an Application. `observability-acg` reports `ErrorOccurred=True`:
  `application references project platform which does not exist (and 2 more)`.
  `grafana-dashboards-acg` selects `k3d-manager/role: app-cluster` clusters, and Hostinger's ArgoCD
  has no cluster Secrets.
- `make appsets-reapply` works on the hub only, so the two sets never move past v1.40.0. They are
  the only reason `k3d-manager-v1.40.0` was kept when the GitHub branches were pruned on 2026-10-22.

## Root cause (probable)

`deploy_observability_acg` pipes both ApplicationSets into `_kubectl apply -f -` with no `--context`.
They land in whatever cluster the current kube context points at. Both clusters use the ArgoCD
namespace `cicd`, so an apply made while the current context was `ubuntu-hostinger` succeeds without
any error. The two sets were created one second apart on 2026-09-29, which fits one run of this
function. Elsewhere in the same plugin, hub writes name `_hub_context="k3d-k3d-cluster"` explicitly
(`observability.sh:21`).

## Fix

- **F1.** In `deploy_observability_acg`, apply both ApplicationSets with
  `--context k3d-k3d-cluster`. Use the same hub-context value as `observability.sh:21`, not a second
  hard-coded copy. Leave the app-cluster calls (`_app_context`) unchanged.
- **F2.** Offline BATS test: with a stubbed `kubectl` and the current context set to an app
  cluster, `deploy_observability_acg` sends both ApplicationSet applies to the hub context.
- **F3.** `CHANGELOG.md` entry.
- **Live (operator, after F1 lands):** delete the two stray sets from Hostinger's ArgoCD:
  `kubectl --context ubuntu-hostinger -n cicd delete applicationset observability-acg grafana-dashboards-acg`.
  First check that `kubectl --context ubuntu-hostinger -n cicd get applications` lists nothing they
  own. Then the `k3d-manager-v1.40.0` branch can be deleted; its tip is already tagged as
  `archive/k3d-manager-v1.40.0` if needed.

## Files

- `scripts/plugins/observability.sh`
- a BATS test under `scripts/tests/` (new or existing file)
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: deploy_observability_acg applies observability-acg and grafana-dashboards-acg to the hub context (k3d-k3d-cluster) whatever the current kube context is.
  - id: M2
    text: App-cluster steps in deploy_observability_acg still target the app-cluster context.
must_not:
  - id: N1
    text: deploy_observability_acg must not apply an ApplicationSet without an explicit hub --context (test red on the pre-fix function).
  - id: N2
    text: No second hard-coded copy of the hub context name is added.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, N1, N2]
    text: The new BATS test passes and fails against the pre-fix observability.sh.
  - id: E2
    kind: live
    proves: [M1]
    text: After the operator deletes the strays and the next deploy_observability_acg run, ubuntu-hostinger cicd has no ApplicationSets and the hub holds both on the current release branch.
interface:
  - deploy_observability_acg [app-context] (scripts/plugins/observability.sh)
  - kubectl --context <ctx> -n cicd get applicationsets
```

## Definition of Done

- [ ] F1–F3 on `k3d-manager-v1.43.5`; only the Files above change.
- [ ] N1 shown red against the pre-fix function.
- [ ] Commit: `fix(observability): apply ACG ApplicationSets to the hub context explicitly`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`.
- Do NOT touch any cluster; the stray deletion is the operator's step.
- Do NOT change the ApplicationSet manifests or `make appsets-reapply`.
