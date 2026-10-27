# Bug: Release Plans hides whether a plan is live-verified

**Status:** OPEN — plan table column reverted at operator request pending Claude review
**Priority:** P3
**Severity:** low — plan verification state was ambiguous in the dashboard
**Release:** v1.43.9 (dashboard bug)
**Branch:** `k3d-manager-v1.43.9`
**Filed:** 2026-10-26, following operator screenshot and request to restore the Live verified column
**Approval:** explicit operator 2026-10-26: restore Live verified and verify it live
**Component:** `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` (panel 107 Plans), `scripts/tests/plugins/grafana_dashboard_bugs.bats`, `docs/guides/grafana-dashboards/k3dm-bugs.md`
**Historical fix commit:** `7ec87a73` (reverted by operator-requested dashboard restoration)
**Revert commit:** `915c55f4`
**Related:** `docs/issues/2026-10-26-plans-live-verification-column.md`
**Historical live evidence:** 2026-10-27 · run hub-grafana-dashboards-sync-1e44141 · env hub/k3d-k3d-cluster/monitoring · scenario k3dm-bugs/plans-live-verification-column-and-width · commit 1e44141ed9059df92223c9e2aee926fc84b89ef6 · proves the prior dashboard version was provisioned; current state was later reverted

## Problem

The Release Plans table had one **Verified** column backed by a mutually exclusive `verification` label. A plan with `LIVE-VERIFIED` status appeared only as verified; the table did not make its live verification state explicit. The Bugs table separately exposes Verified, Live-verified, timestamps, commits, and live evidence, while Plans only has the status indicators available from each plan document.

## Previous implementation (reverted)

Panel 107 now derives two display labels from the plan's existing `verification` value:

- **Verified** is checked for `verified` and `live_verified`.
- **Live verified** is checked only for `live_verified`.
- Other values display `-`.

The two indicators describe the plan's recorded status. They do not identify who verified the plan or present a verifier, timestamp, commit, or evidence record; consult the linked plan document for that information. The columns are fixed-width, and their combined configured widths total 1,320 px against the 1,350 px laptop layout budget.

## Verification

- `bats scripts/tests/plugins/grafana_dashboard_bugs.bats`: 38/38 passed.
- Dashboard JSON parsed successfully; `git diff --check`, `_agent_checkpoint`, `_agent_lint`, and `_agent_audit` passed.
- Live: Argo CD `hub-grafana-dashboards` reconciled revision `1e44141ed9059df92223c9e2aee926fc84b89ef6` with `Synced`, `Healthy`, and operation `Succeeded`. The live `grafana-dashboard-bugs` ConfigMap contains panel 107 with both columns, the separate `live_verified` projection, and a 1,320 px total configured width. Grafana's `grafana-sc-dashboard` sidecar wrote `/tmp/dashboards/k3dm-bugs.json`; Grafana logged `starting to provision dashboards` then `finished to provision dashboards`.
- A Grafana API request without credentials returned HTTP 401, so it did not provide API-level inspection. No browser screenshot was captured; live evidence here proves the ConfigMap and Grafana provisioning path consumed the updated dashboard.
