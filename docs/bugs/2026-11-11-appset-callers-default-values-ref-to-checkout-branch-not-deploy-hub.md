# Bug: three ApplicationSet appliers still default the values ref to the checkout branch, undoing deploy/hub

**Status:** LANDED `37bf2b5f` 2026-11-11 (Luna, 2 rounds; independent verifier pass, red on `8f9b33ed`; Flash 3.8 review: land after fixes, test-only finding open below; Claude 8/8 red/green) — found 2026-11-11 from a Hermes values_branch incident
**Priority:** P2
**Waiting on:** live check — since 2026-11-11 (E3 after promote)
**Severity:** after any cluster-up/preflight/observability deploy run from a release-branch checkout, hub Applications track that branch instead of `deploy/hub`, so unpromoted config deploys and promote is bypassed. Workaround: approve Hermes repair `deploy_argocd_applicationsets --confirm` or run `make appsets-reapply` afterwards.
**Introduced by:** `897cfe72` (v1.43.15, hub deploy ref `deploy/hub`) — these writers were not in its Contract readers list
**Should have been caught by:** spec (Contract readers grep)
**Prior art:** exact-slug glob: none; related `docs/bugs/2026-11-10-hub-promote-discards-cve-promoter-commits.md` (different reader). `make find-similar-docs` not run (M4).
**Approval:** Claude, 2026-11-11; dispatch go: operator, 2026-11-11 ("go ahead to dispatch task. you can pick up agent this time"), on Claude's recommendation to fix before the v1.43.15 PR; intents shown in the dispatch report
**Intent approved:** operator, 2026-11-11
**Filed:** 2026-11-11

## What happened

Hermes, 2026-11-11T19:52:29Z: `values_branch: 15 apps (16 source refs) not on deploy/hub: blackbox-exporter@k3d-manager-v1.43.15,
hub-grafana-dashboards@…, hub-loki@… (+12 more)`, offering repair `r9-d9add2e2` (reapply pinned to deploy/hub).

## Cause

`deploy_argocd_applicationsets` defaults to `deploy/hub` (`scripts/plugins/argocd.sh:1289`), but these still default
`K3D_MANAGER_BRANCH` to `git rev-parse --abbrev-ref HEAD`:

- `bin/cluster-preflight:51` (passed on at :218, :235, :263)
- `scripts/lib/providers/k3s-hostinger.sh:893`
- `scripts/plugins/observability.sh:23` (`deploy_observability`) and `:676` (`deploy_observability_acg`)

Which one ran just before 19:52Z is not confirmed (the hub is not reachable from the M4); the affected apps are hub
observability ones, consistent with `deploy_observability` or `cluster-preflight`.

## Fix direction

Default each to `deploy/hub` (or a shared helper), keep the env override; tests show each applier's rendered
`targetRevision` is `deploy/hub` with the variable unset from a release-branch checkout (red on pre-fix code).

## Contract readers

Contract: the `K3D_MANAGER_BRANCH` env var, i.e. the values ref rendered into hub ApplicationSets (`grep -rn K3D_MANAGER_BRANCH bin scripts Makefile`, 2026-11-11).

- **Writers that change** (default becomes `deploy/hub`, env override kept): `bin/cluster-preflight:51`;
  `scripts/lib/providers/k3s-hostinger.sh:893` (`_hostinger_reapply_gitops_applicationsets`, applies to the hub via
  `_argocd_hub_kubectl_cmd`); `scripts/plugins/observability.sh:23` (`deploy_observability`) and `:676`
  (`deploy_observability_acg`).
- **Writers unchanged (already `deploy/hub`)**: `scripts/plugins/argocd.sh:1289`; `Makefile:461` (`appsets-reapply`);
  `scripts/lib/hermes/repairs.py:226` (r9 repair).
- **Readers unchanged**: the ApplicationSet templates that render it (`scripts/etc/argocd/applicationsets/*.yaml`:
  `targetRevision`/`revision`); `scripts/plugins/argocd.sh:1236-1252,2055` (values-branch confirm/check, default already
  `deploy/hub`); `scripts/plugins/argocd.sh:1666` (`ARGOCD_APP_CLUSTER_RELEASE` fallback label only);
  `bin/cluster-status:294` (message text only).
- **Behaviour change for people**: running cluster-preflight or an observability deploy from a release branch no longer
  points hub apps at that branch. To test unpromoted config on purpose, set `K3D_MANAGER_BRANCH=<branch>` explicitly.

## Acceptance

```yaml
must:
  - M1: with K3D_MANAGER_BRANCH unset, run from a checkout on a branch other than deploy/hub, each of the four appliers (bin/cluster-preflight, _hostinger_reapply_gitops_applicationsets, deploy_observability, deploy_observability_acg) applies ApplicationSets whose every targetRevision/revision that the template takes from K3D_MANAGER_BRANCH is deploy/hub
  - M2: with K3D_MANAGER_BRANCH set to another value, each of the four appliers applies that value
must_not:
  - N1: any of the four appliers applies the checkout's branch name as a values ref when K3D_MANAGER_BRANCH is unset
evidence:
  - E1: {proves: [M1, N1], offline: true, intent: "deploying observability or running preflight from a release branch keeps hub apps on deploy/hub"}
  - E2: {proves: [M2], offline: true, intent: "you can still point hub apps at a branch on purpose by setting K3D_MANAGER_BRANCH"}
  - E3: {proves: [M1], live: true, intent: "after the next observability deploy on the hub, make appsets-check reports every app on deploy/hub and Hermes raises no values_branch incident"}
interface:
  - bin/cluster-preflight NAME MODE (kubectl stubbed; the stub records the YAML piped to `apply -f -`)
  - ./scripts/k3d-manager deploy_observability --confirm and deploy_observability_acg --confirm (kubectl/helm stubbed)
  - _hostinger_reapply_gitops_applicationsets in scripts/lib/providers/k3s-hostinger.sh (hub kubectl stubbed)
  - a scratch git checkout on a branch named like k3d-manager-v9.9.9 as the repo the code reads its branch from
```

Stubs record what is piped to them and print nothing, so no output is imitated. Each test first asserts that it targets
the scratch checkout and the kubectl stub, not the real tree or a real cluster.

## Files

- `bin/cluster-preflight`
- `scripts/lib/providers/k3s-hostinger.sh`
- `scripts/plugins/observability.sh`
- `scripts/tests/bin/appset_values_ref_default.bats` (new)

## Definition of done (worker)

Before your last message, do all of these and paste the evidence:
1. Run every test suite that covers a file you changed (find them with `grep -rln` on each file name under
   `scripts/tests`), not only the new tests. For each, give the command, the exit code and every error line. An error you
   can't explain is a failure, not a pass. If the sandbox blocks a test, say so and name it.
2. For N1: revert each applier's default to the checkout branch in turn, run its test, show it red, restore it and show it
   green. List any applier whose test stayed green with the guard broken.
3. No read-only real-data run is possible (applying ApplicationSets moves the hub); say so.
4. List every place where you chose something the spec did not decide.
5. Never run `git config --global`, `make install-*`, or anything against a real cluster; set git identity through env
   vars or the scratch repo's own config.


## Review findings carried (Flash 3.8, 2026-11-11)

- should-fix, test only: the preflight `kubectl get applications.argoproj.io` stub omits `spec.destination.name`, so
  tests 1 and 2 reach the wait timeout and do not assert exit status. Their YAML assertions still hold. For triage.
- nit: an explicitly empty `K3D_MANAGER_BRANCH` falls back to `deploy/hub` (same as `scripts/plugins/argocd.sh:1289`). No change.
