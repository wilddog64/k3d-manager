# Bug: three ApplicationSet appliers still default the values ref to the checkout branch, undoing deploy/hub

**Status:** OPEN — found 2026-11-11 from a Hermes values_branch incident
**Priority:** P2
**Waiting on:** dispatch
**Severity:** after any cluster-up/preflight/observability deploy run from a release-branch checkout, hub Applications track that branch instead of `deploy/hub`, so unpromoted config deploys and promote is bypassed. Workaround: approve Hermes repair `deploy_argocd_applicationsets --confirm` or run `make appsets-reapply` afterwards.
**Introduced by:** the hub deploy-ref change (v1.44.0 spec, deploy/hub) — these readers were not in its Contract readers list
**Should have been caught by:** spec (Contract readers grep)
**Prior art:** exact-slug glob: none; related `docs/bugs/2026-11-10-hub-promote-discards-cve-promoter-commits.md` (different reader). `make find-similar-docs` not run (M4).
**Approval:** Claude, 2026-11-11
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
