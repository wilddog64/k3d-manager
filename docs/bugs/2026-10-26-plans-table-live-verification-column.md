# Bug: Release Plans hides whether a plan is live-verified

**Status:** LIVE-VERIFIED — operator screenshots confirm E2 on 2026-10-27
**Live evidence:** 2026-10-27 · run operator-plans-positive-and-unknown-indicators · env m4-hub-grafana · scenario plans-positive-and-unknown-indicators · commit 9893651f4fd4127db692bf2d1743e070a7683284 · proves E2
**Priority:** P3
**Fix commit:** `9893651f4fd4127db692bf2d1743e070a7683284`
**Severity:** low — plan verification state was ambiguous in the dashboard
**Release:** v1.43.9 (dashboard bug)
**Branch:** `k3d-manager-v1.43.9`
**Filed:** 2026-10-26, following operator screenshot and request to restore the Live verified column
**Approval:** explicit operator 2026-10-26; renewed 2026-10-27 selection for Luna implementation and sequential operator live checks
**Dispatch:** go — model `gpt-6-luna`; task `plans-live-verification-column-luna`
**Component:** `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` (panel 107 Plans), `scripts/tests/plugins/grafana_dashboard_bugs.bats`, `docs/guides/grafana-dashboards/k3dm-bugs.md`
**Historical fix commit:** `7ec87a73` (reverted by operator-requested dashboard restoration)
**Revert commit:** `915c55f4`
**Related:** `docs/issues/2026-10-26-plans-live-verification-column.md`
**Historical live evidence:** 2026-10-27 · run hub-grafana-dashboards-sync-1e44141 · env hub/k3d-k3d-cluster/monitoring · scenario k3dm-bugs/plans-live-verification-column-and-width · commit 1e44141ed9059df92223c9e2aee926fc84b89ef6 · proves the prior dashboard version was provisioned; current state was later reverted

## Problem

The Release Plans table had one **Verified** column backed by a mutually exclusive `verification` label. A plan with `LIVE-VERIFIED` status appeared only as verified; the table did not make its live verification state explicit. The Bugs table separately exposes Verified, Live-verified, timestamps, commits, and live evidence, while Plans only has the status indicators available from each plan document.

## Previous implementation (reverted)

The reverted implementation derived two display labels from the plan's existing `verification` value:

- **Verified** is checked for `verified` and `live_verified`.
- **Live verified** is checked only for `live_verified`.
- Other values display `-`.

The two indicators describe the plan's recorded status. They do not identify who verified the plan or present a verifier, timestamp, commit, or evidence record; consult the linked plan document for that information. The columns are fixed-width, and their combined configured widths total 1,320 px against the 1,350 px laptop layout budget.

## Verification

- `bats scripts/tests/plugins/grafana_dashboard_bugs.bats`: 38/38 passed.
- Dashboard JSON parsed successfully; `git diff --check`, `_agent_checkpoint`, `_agent_lint`, and `_agent_audit` passed.
- Live: Argo CD `hub-grafana-dashboards` reconciled revision `1e44141ed9059df92223c9e2aee926fc84b89ef6` with `Synced`, `Healthy`, and operation `Succeeded`. The live `grafana-dashboard-bugs` ConfigMap contains panel 107 with both columns, the separate `live_verified` projection, and a 1,320 px total configured width. Grafana's `grafana-sc-dashboard` sidecar wrote `/tmp/dashboards/k3dm-bugs.json`; Grafana logged `starting to provision dashboards` then `finished to provision dashboards`.
- A Grafana API request without credentials returned HTTP 401, so it did not provide API-level inspection. No browser screenshot was captured; live evidence here proves the ConfigMap and Grafana provisioning path consumed the updated dashboard.

## Current implementation scope

The new operator instruction supersedes the earlier hold only for this separate
column enhancement. Preserve the now LIVE-VERIFIED Dispatch approval/task split,
not-recorded mapping, ledger-aware documentation-stale blocker, filters and
links from `608b90a1`. Do not restore the whole old dashboard or undo that fix.
The earlier task's single-column constraint described its scope; this task
explicitly adds the separately requested Live verified column.

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`
- `scripts/tests/plugins/grafana_dashboard_bugs.bats`
- `scripts/tests/bin/test_vectordb_bug_metrics.py`
- `docs/guides/grafana-dashboards.md`
- `CHANGELOG.md`

## Acceptance

- M1: Separate Verified and Live verified display columns derive only from the
  existing plan verification label. Verified is positive for verified and
  live_verified; Live verified is positive only for live_verified. Other states
  display a dash. Preserve raw source metadata, including unknown and n/a.
- M2: Never derive verification from landed/approved. Preserve all current
  lifecycle/blocker/filter/link behavior and one row per source plan.
- M3: Keep total fixed column widths <=1350 px and document status-only meaning.
- N1: Do not edit plan Status/Approval/Dispatch or exporter/ledger contracts.
- E1 offline: dashboard BATS and focused vectordb_bug_metrics pytest, including
  actual PromQL lifecycle fixtures with positive verified/live_verified cases
  when promtool is available. Update exact-label expectations for legitimate
  new display labels while continuing to assert raw source fields unchanged.
  Show new checks red on the original single-column panel.
- E2 live: operator screenshot after approved rollout demonstrates distinct
  indicators against recorded plan statuses; no invented verifier/timestamp.

## Dispatch rules — operator batch 2026-10-27

The operator explicitly selected this existing bug for implementation by
GPT-6-Luna, independent offline review, and operator live verification one fix
at a time. This is implementation authorization; no worker may deploy, restart
services, contact live clusters/registries/providers, create accounts, rotate
credentials, or run live tests. Work only in the isolated task worktree and the
Files allowlist. Do not edit this spec, memory-bank, or source plan statuses.
Do not stage, commit, push, or create PRs. Preserve DO NOT REMOVE comments.
Add meaningful regressions and show them red on the original behavior before
reporting green. Run focused tests, syntax/lint, and git diff --check; report
actual outputs and any unmet acceptance honestly. Use <=8 if blocks in new or
refactored functions. Report legacy budget conflicts instead of raising limits.
The coordinator will run audit/lint on staged changes before committing.

## Independent batch review

Implementation `9893651f` was independently reviewed within its allowlist,
committed on its isolated task branch, rebased/tested/landed through the dispatcher.
Full gate output and pre-fix regression evidence are recorded in
`docs/issues/2026-10-27-six-bug-luna-batch.md`. No assistant dashboard sync or live
probe was run. Operator live verification is strictly one fix at a time.

Post-rebase: 111 Python tests passed including actual Prometheus lifecycle/
verification fixtures, Ruff passed, all 38 dashboard BATS passed, staged audit/
lint/diff passed. Both actual-query regressions fail on the original single-
column panel. Raw verification is preserved; derived indicators include dash
defaults and correct verified/live_verified behavior. Fixed widths total 1,347px.
Existing Dispatch approval/task, stale-document blockers and filters/links remain
intact. The old negative single-column assertion was replaced with projection
checks plus exact raw-label fixtures, with the required audit marker explaining
this legitimate replacement. Operator check is queued behind probe-age check 1.
