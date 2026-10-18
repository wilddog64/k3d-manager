# Bug: PR Checks dashboard tables show `No data` when no PR is open, which reads as a fault

**Filed:** 2026-10-18 (Claude, from an operator screenshot)
**Status:** FIXED — 2026-10-18 by Claude (operator: "if it is small enough then you go work on it"); BATS 3/3, N1 red on pre-fix; E2 live pending
**Priority:** P3 — cosmetic; the collector and dashboard are healthy
**Severity:** low
**Approval:** approved — operator, 2026-10-18: "yes, file that bug" / "go ahead file a P3 tweak" (dispatch not yet approved)
**Release:** v1.43.4 (bug; exempt from the plan cap)
**Component:** `scripts/etc/argocd/platform-ops/grafana-dashboard-pr-checks.yaml`, `docs/guides/grafana-dashboards.md`
**Related:** `docs/plans/v1.43.3-pr-checks-dashboard.md`

## Problem

On 2026-10-18 the **k3dm PR Checks** dashboard showed `No data` in its **Open PRs** (panel 5) and
**Checks per PR** (panel 6) tables. Nothing was wrong: `k3d-manager` and `lib-foundation` both had
0 open PRs, the **Open PRs** stat read 0, **Last scrape** was 3 minutes old and **GitHub read** was
`ok`. The collector only emits `k3dm_pr_info`, `k3dm_pr_overall`, `k3dm_pr_check_state` and
`k3dm_pr_check_duration_seconds` for PRs that are currently open, so an empty table is the correct
result. Grafana's default `No data` text makes that look like a broken producer, which is exactly
how the operator read it.

## Fix

### 1. `scripts/etc/argocd/platform-ops/grafana-dashboard-pr-checks.yaml`

Add `"noValue"` to `fieldConfig.defaults` of panel 5 and panel 6 only. Keep the file's compact
JSON style and change nothing else on those lines.

- Panel 5 (`"title":"Open PRs"`, type `table`): `"noValue": "No open PRs"`
- Panel 6 (`"title":"Checks per PR"`, type `table`): `"noValue": "No open PRs — no checks to show"`

The stat panels already use `or vector(0)` and must not change. If the hub Grafana version does not
render `noValue` on an empty table (E2 shows `No data` still), say so in the report rather than
switching panel types; the fallback is decided by Claude.

### 2. `docs/guides/grafana-dashboards.md`

In the `### k3dm PR Checks (`k3dm-pr-checks`) — hub` section, after the sentence ending
"Merged or closed PRs disappear on the next good poll.", add:

```
With no open PRs the two tables read `No open PRs`; that is normal, and **Last scrape** and
**GitHub read** are the panels that show whether the collector is healthy.
```

### 3. Test `scripts/tests/plugins/grafana_dashboard_pr_checks.bats`

Add one test: panels 5 and 6 each have a non-empty `fieldConfig.defaults.noValue` containing
`No open PRs`, and every stat panel's expression is unchanged from pre-fix (still ends in
`or vector(0)` where it did before).

## Acceptance

```yaml
must:
  - id: M1
    text: In grafana-dashboard-pr-checks.yaml, the table panels titled "Open PRs" and "Checks per PR" each set fieldConfig.defaults.noValue to a string containing "No open PRs".
  - id: M2
    text: The embedded JSON still parses, uid stays k3dm-pr-checks, and make validate-manifests passes.
  - id: M3
    text: The guide's k3dm PR Checks section says empty tables read "No open PRs" and names Last scrape and GitHub read as the health panels.
must_not:
  - id: N1
    text: The two tables must not fall back to Grafana's default "No data" text when no PR is open (red on pre-fix, where neither panel sets noValue).
  - id: N2
    text: No panel's targets, stat expressions, mappings or panel ids change; no other dashboard file changes.
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    text: bats scripts/tests/plugins/grafana_dashboard_pr_checks.bats scripts/tests/plugins/grafana_dashboard_appsets.bats plus make validate-manifests; N1 shown red against the pre-fix dashboard from git show into a temp directory.
  - id: E2
    proves: [M1, N1]
    kind: live
    text: After ArgoCD app hub-grafana-dashboards syncs the commit, with no open PR, the operator's screenshot shows both tables reading "No open PRs" instead of "No data".
interface:
  - scripts/etc/argocd/platform-ops/grafana-dashboard-pr-checks.yaml (ConfigMap, data key pr-checks.json, panels 5 and 6)
  - docs/guides/grafana-dashboards.md (k3dm PR Checks section)
```

## Definition of Done

- [ ] Files: the dashboard ConfigMap, the guide, the BATS file — nothing else.
- [ ] E1 commands green; N1 red on the pre-fix dashboard, output pasted.
- [ ] Commit message verbatim: `fix(grafana): label the PR Checks tables "No open PRs" when nothing is open`
- [ ] Pushed to `origin/k3d-manager-v1.43.4`; `git rev-parse origin/k3d-manager-v1.43.4` matches.
- [ ] memory-bank `activeContext.md` and `progress.md` updated with the SHA.

## What NOT to Do

- Do NOT create a PR, merge, or commit to `main`. Do NOT use `--no-verify`.
- Do NOT modify files outside the listed targets, any ApplicationSet, `bin/`, the Hermes collector, or `scripts/lib/foundation/`.
- Do NOT apply anything to a cluster or call Grafana or GitHub.
