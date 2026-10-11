# Bug: the first scheduled hub data export failed, no alert fired, and the drill freshness workflow cannot find its script

**Branch:** `k3d-manager-v1.43.0`
**Filed:** 2026-10-11
**Status:** FIXED in code (2026-10-11, Claude) — live proof pending the operator's kickstart run and rule apply
**Priority:** P1
**Severity:** High — the daily export, the v1.43.0 release gate, produced nothing and nothing said so
**Files:** `scripts/plugins/hub_data.sh`, `scripts/tests/plugins/hub_data.bats`,
`scripts/etc/dr/drill-freshness.yml`, `scripts/tests/plugins/dr_drill_freshness.bats`,
`docs/howto/hub-dr-drill.md`, `CHANGELOG.md`

## Symptom

Three separate failures on the night of 2026-10-10 → 2026-10-11.

1. `~/Library/Logs/k3dm-hub-data-export.log` at 03:30:

   ```
   ERROR: [hub-data] missing age recipient: ./scripts/etc/dr/age-recipient.txt
   ```

   The Pushgateway got `k3dm_hub_data_export_last_run_success 0`.
2. No `HubDataExport*` alert fired. `ALERTS{alertname=~"HubDataExport.*"}` was empty, and the
   Prometheus rules API had no `HubDataExportFailed` rule at all.
3. The data repo's `Hub DR drill freshness` workflow failed at 09:30 UTC, and GitHub e-mailed
   "All jobs have failed":

   ```
   bash: k3dm-manager/scripts/etc/dr/drill-freshness.sh: No such file or directory
   ##[error]Process completed with exit code 127.
   ```

## Root cause

1. **A repo path that is relative to the caller's directory.** `hub_data.sh` defaulted
   `K3DM_HUB_DATA_AGE_RECIPIENT` (and the drill's Keycloak postgres manifest) to
   `${REPO_ROOT:-.}/scripts/etc/dr/...`. The dispatcher never sets `REPO_ROOT`. Every manual run
   was made from the repo root, where `.` happens to be right. launchd starts the job in `/`. The
   manual runs and the tests (which set the recipient explicitly) could not catch it.
2. **The alert rules were never applied.** `dr.alerts` lives in
   `scripts/etc/argocd/platform-ops/prometheusrule.yaml`. ArgoCD's `hub-platform-ops` includes only
   `app-cluster-kubeconfig-externalsecret.yaml`, and the file reaches the hub only through
   `make platform-ops` (`deploy_argocd_platform_ops`). The how-to said "The three alerts need no
   step: ArgoCD syncs `hub-platform-ops`", and the 2026-10-10 memory-bank entry repeated it. The
   live `argocd-degraded` rule has four groups (argocd, trivy-operator, e2e, hermes) and no
   `dr.alerts`, so the `DRDrill*` alerts are missing too.
3. **The workflow template points at a k3d-manager path.** The how-to installs
   `drill-freshness.sh` at the root of the data repo's `main`, and the workflow's second checkout
   is the data repo's `main` (no `repository:`), placed at `k3dm-manager/`. The `run:` line used
   `k3dm-manager/scripts/etc/dr/drill-freshness.sh`, which exists only in k3d-manager. Not related
   to the export; the first scheduled run was the first time it ran.

## Fix

1. `hub_data.sh` resolves `_HUB_DATA_ROOT` from the plugin's own path (`REPO_ROOT` still
   overrides) and uses it for both defaults. New BATS test sources the plugin from `/` and asserts
   the recipient is the repo's readable file and that no `REPO_ROOT:-.` default remains; it fails
   on the old plugin.
2. `docs/howto/hub-dr-drill.md`: the alerts step is now an explicit `kubectl apply` of
   `prometheusrule.yaml`, and a new step proves the scheduled path with
   `launchctl kickstart` instead of only a manual run.
3. `drill-freshness.yml` runs `bash k3dm-manager/drill-freshness.sh results`. New BATS test pins
   the run line to the how-to's install location; it fails on the old template. The installed copy
   of `drill-freshness.sh` on the data repo's `main` is byte-identical to the repo's.

## Operator steps (live)

1. The LaunchAgent needs no reinstall: the plist is unchanged, and the fix is in the plugin it
   runs. Pull the branch, then run the job as launchd would:
   `launchctl kickstart gui/$(id -u)/com.k3d-manager.hub-data-export`, then
   `tail -30 ~/Library/Logs/k3dm-hub-data-export.log`. Expect a pushed export and
   `k3dm_hub_data_export_last_run_success 1`.
2. `kubectl --context k3d-k3d-cluster apply -f scripts/etc/argocd/platform-ops/prometheusrule.yaml`,
   then confirm `HubDataExportFailed` appears in the rules API. The apply also brings the other four
   groups up to this branch.
3. Update `.github/workflows/drill-freshness.yml` on the data repo's `main` with the one-line `run:`
   change, then `gh workflow run "Hub DR drill freshness" --repo wilddog64/k3dm-hub-data` and
   confirm it passes (newest result `20261010T182508Z`).

## Lesson

A scheduled job is not proven by a manual run from the repo. The setup now ends with a
`launchctl kickstart`, which runs it the way the schedule will.
