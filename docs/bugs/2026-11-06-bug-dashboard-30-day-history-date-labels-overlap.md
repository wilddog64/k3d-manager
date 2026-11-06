# Bug: the 30-day open-bug history panel draws its date labels on top of each other

**Status:** OPEN — filed and dispatched to Luna 2026-11-06
**Priority:** P3
**Severity:** low. The bars and tooltip still work; the x-axis cannot be read.
**Approval:** operator reported it 2026-11-06: "this became unreadable". Non-critical, Claude files and dispatches.
**Filed:** 2026-11-06
**Detected by:** operator, on the M5 Grafana
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/plans/v1.43.14-bug-open-history-from-git.md` (added the panel)

## Problem

Panel 18, "Open by priority, last 30 days (from git)", in `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` is a `barchart` whose x field is a `YYYY-MM-DD` string. It has `"xTickLabelRotation": 0` and no `xTickLabelSpacing`, so Grafana draws a horizontal label for every bar. The panel is 12 grid columns wide. With about 30 days of data the labels overlap until no date can be read.

## Fix

In panel 18's `options` only, set `"xTickLabelRotation": -45` and `"xTickLabelSpacing": 100`. The tooltip still gives the date of every bar. Do not change the query, the transformations, or any other panel.

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`
- `scripts/tests/plugins/grafana_dashboard_bugs.bats`

## Acceptance

```yaml
must:
  - id: M1
    text: "The panel titled 'Open by priority, last 30 days (from git)' has a nonzero xTickLabelRotation and an xTickLabelSpacing greater than 0."
must_not:
  - id: N1
    text: "The change does not alter that panel's query, transformations, x field or stacking, or any other panel in the dashboard (paired with M1)."
evidence:
  - {id: E1, proves: [M1, N1], kind: offline, text: "A test parsing the dashboard JSON from the YAML; M1 red on the pre-fix commit; N1 compared against the pre-fix dashboard and red by a mutant."}
  - {id: E2, proves: [M1], kind: live, text: "After the hub reads the release branch (make appsets-check, reapply if needed), the operator confirms the dates on the M5 Grafana panel can be read."}
interface:
  - "scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml, key k3dm-bugs.json"
```
