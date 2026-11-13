# Bug: promoted PrometheusRule changes never reach the hub Prometheus; `K3dmPromoteWaiting` is not loaded

**Status:** OPEN — captured 2026-11-13 by Claude while running plan 3 E6 (live)
**Priority:** P2 (new and changed alerts silently absent after a promote; workaround `make prometheus-rules` on the M5)
**Waiting on:** operator decision — since 2026-11-13
**Introduced by:** pre-existing (rules apply only through `make prometheus-rules` / observability deploy); exposed by `c763e239` (v1.44.0 plan 3)
**Should have been caught by:** spec (plan 3 lists no deploy step for its rule; E6 is the first live check that needs it)
**Prior art:** exact-slug glob: none; `docs/bugs/2026-10-03-sandbox-make-up-host-alias-and-rules-crd-race.md` (title only, different). `make find-similar-docs` not run

## Symptom

Read-only probes of the M5 on 2026-11-13, 14:30Z:
- deploy/hub = `e6b62305`, and `git show e6b62305:scripts/etc/prometheus/rules/repo-sync.yaml` has four alerts: K3dmRepoSyncStale, K3dmDeployPending, K3dmPromoteWaiting, K3dmPromoteLookupFailed.
- The hub Prometheus (`127.0.0.1:19091/api/v1/rules`) group `repo.sync` has only `K3dmRepoSyncStale` and `K3dmDeployPending`.
- The metric is there: Pushgateway has `k3dm_repo_sync_promotable{sha="e9c375c",instance="m5-air"} 1` since 14:27:58Z. So the alert can never fire.

## Root cause

- PrometheusRules are not GitOps-managed. They reach the cluster only via `make prometheus-rules` (`Makefile:1367`) or a full observability deploy (`scripts/plugins/observability.sh:58`).
- The promote sequence (`make hub-promote`, `make appsets-check`, `make platform-ops`) does not include it.
- repo-sync's `deploy_pending` steps are `platform-ops`, `appsets-reapply` and `webhook-restart` (`bin/k3dm-repo-sync` ~499). A promote that changes `scripts/etc/prometheus/rules/` therefore raises no `K3dmDeployPending`.

## Options (operator decision)

1. Add a `prometheus-rules` deploy_pending step to repo-sync, keyed on `scripts/etc/prometheus/rules/` changes, with a marker the way platform-ops has one, so `K3dmDeployPending` names it.
2. Manage the hub rules through an ArgoCD Application reading deploy/hub (like platform-ops), which removes the manual step.
3. Make `make platform-ops` also apply the rules.

## Unblock E6 now

The operator runs `make prometheus-rules` on the M5. It is additive `kubectl apply` of the rule files.
