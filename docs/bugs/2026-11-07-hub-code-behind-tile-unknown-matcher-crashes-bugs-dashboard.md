# Bug: the Hub code behind tile uses an unknown field matcher and crashes the Bugs dashboard

**Filed:** 2026-11-07
**Branch:** `k3d-manager-v1.43.14`
**Status:** LANDED 2026-11-07 — `73120c90` (Luna); independent verifier pending
**Fix commit:** 73120c90
**Priority:** P1 — the whole Bugs dashboard fails to render; there is no workaround in the UI
**Waiting on:** live check — since 2026-11-07
**Approval:** explicit 2026-11-07 "go ahead." (operator, dispatch go)
**Severity:** high

## Symptom

On 2026-11-07, during the first live check of `dc5f6bb0` (`docs/bugs/2026-11-06-hub-code-lag-invisible-and-no-catch-up-step.md`, E3), the operator opened the Bugs dashboard on `grafana.3ai-talk.org` and got Grafana's page-level error:

`An unexpected error happened` — `Error: "byRefId" not found in: anyMatch,allMatch,invertMatch,alwaysMatch,neverMatch,byType,byTypes,numeric,time,byName,byRegexp,byNames,byRegexpOrNames,...`

The dashboard sync was `k3d-cluster-grafana-dashboards` Synced at `8bab7807`. The tile's Prometheus series is correct (Claude, 2026-11-07 03:50 PST: `k3dm_hub_checkout_code_commits_behind` = 0, equal to `git rev-list` on the M5), so the data is fine and only the panel JSON is wrong.

The operator raised that the error page shows a stack trace (2026-11-07: "the exception should not explore on the page ... that's security concern"). It is Grafana's client-side error boundary: it lists the hashed bundle URLs the browser already loaded and Grafana's open-source matcher names. It has no server paths, config or secrets, and only someone who can already load Grafana sees it. Grafana 11.4 has no setting to hide it, so the way to stop it appearing is to stop invalid panel JSON reaching the hub, which is the guard below.

## Root cause

`scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`, panel id 19 (`Hub code behind`), has a field override with `"matcher": {"id": "byRefId", "options": "B"}`. A field override's matcher is looked up in Grafana's **field** matcher registry. In Grafana 11.4.0, `byRefId` is a **frame** matcher (`FrameMatcherID.byRefId`); the field matcher for a query refId is `byFrameRefID`. An unknown field matcher throws during render, and the error takes down the whole dashboard, not just the panel.

`scripts/tests/plugins/grafana_dashboard_bugs.bats:37` asserts the same wrong id, so the code and the test share the contract and every offline check passed. This is the failure the "stubs are captured, not imagined" rule warns about.

Captured registry, from `packages/grafana-data/src/transformations/matchers/ids.ts` at tag `v11.4.0` (fetched by Claude with `gh api` on 2026-11-07; hub Grafana is 11.4.0):

- `MatcherID`: `anyMatch`, `allMatch`, `invertMatch`, `alwaysMatch`, `neverMatch`
- `FieldMatcherID`: `numeric`, `time`, `first`, `firstTimeField`, `byType`, `byTypes`, `byName`, `byNames`, `byRegexp`, `byRegexpOrNames`, `byFrameRefID`, `byValue`
- `FrameMatcherID` (not valid in a field override): `byName`, `byRefId`, `byIndex`

## Fix

1. In `grafana-dashboard-bugs.yaml`, panel id 19, change the override matcher id from `byRefId` to `byFrameRefID`. Options stay `"B"`. Nothing else in the panel changes.
2. In `grafana_dashboard_bugs.bats`, change the line 37 assertion to expect `byFrameRefID`.
3. Add a guard test in `scripts/tests/bin/test_dashboard_queries.py`: for every dashboard JSON under `scripts/etc/argocd/platform-ops/grafana-dashboard-*.yaml`, every `fieldConfig.overrides[].matcher.id` must be in the allow-list above (`MatcherID` plus `FieldMatcherID`). Keep the list as a constant with a comment naming the source file, tag and capture date. Paired control: the same check rejects `byRefId` and `byIndex` in a synthetic override.
4. `CHANGELOG.md`: one bullet at the end of `[Unreleased]`.

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`
- `scripts/tests/plugins/grafana_dashboard_bugs.bats`
- `scripts/tests/bin/test_dashboard_queries.py`
- `CHANGELOG.md`

## Gates

`bats scripts/tests/plugins/grafana_dashboard_bugs.bats`, and `pytest scripts/tests/bin/test_dashboard_queries.py` with `PATH` including a Python that has PyYAML. Paste the output, including failures.

## What NOT to Do

- Do NOT change the panel's queries, title, position or thresholds.
- Do NOT weaken the allow-list by reading it from the dashboards themselves.
- Do NOT commit, push or create a PR. Claude reviews and commits.
- Do NOT touch `memory-bank/` or any file outside the Files list.

## Acceptance

```yaml
interface:
  - "scripts/etc/argocd/platform-ops/grafana-dashboard-*.yaml: the embedded dashboard JSON, fieldConfig.overrides[].matcher.id"
  - "scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml: the panel with id 19, titled Hub code behind"
must:
  - id: M1
    text: "Panel 19's override that targets query B uses matcher id byFrameRefID with options B."
  - id: M2
    text: "Every field override matcher id in every platform-ops dashboard is one of: anyMatch, allMatch, invertMatch, alwaysMatch, neverMatch, numeric, time, first, firstTimeField, byType, byTypes, byName, byNames, byRegexp, byRegexpOrNames, byFrameRefID, byValue (Grafana 11.4.0 MatcherID and FieldMatcherID)."
must_not:
  - id: N1
    text: "No field override in any platform-ops dashboard uses byRefId or byIndex. Paired control: the guard reports a synthetic override using byRefId as a failure."
  - id: N2
    text: "Panel 19's queries, title and gridPos are unchanged from dc5f6bb0."
evidence:
  - id: E1
    proves: [M1, M2, N1, N2]
    kind: offline
    what: "Independent verifier, tests from this block only; N1 shown red against dc5f6bb0."
  - id: E2
    proves: [M1]
    kind: live
    what: "Operator: after the dashboard syncs, the Bugs dashboard renders and the Hub code behind tile shows the behind count and the release state."
```
