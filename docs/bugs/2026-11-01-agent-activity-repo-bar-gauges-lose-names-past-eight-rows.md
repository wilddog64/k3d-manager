# Bug: Agent Activity "Untracked by repo" and "Tokens by repo" lose every bar name once the window holds ~20 repos

**Status:** OPEN — dispatch to Luna after the re-read share bug lands (same dashboard file)
**Priority:** P3
**Severity:** low — the bar values are correct; the operator cannot tell which repo a bar belongs to; no runtime impact
**Approval:** operator, 2026-11-01 ("file two P3 bug then all to Luna")
**Filed:** 2026-11-01
**Detected by:** operator (screenshot 514, agent-activity, Window 30d), root cause by Claude
**Affected:** `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml` (panels 54 "Untracked by repo", 56 "Tokens by repo")
**Branch:** `k3d-manager-v1.43.13`
**Related:** `docs/bugs/2026-10-24-agent-activity-titles-and-bar-labels-truncated.md` (Recurrence 2026-11-01 records the symptom; this file is the dispatchable fix); `docs/plans/v1.43.15-cost-attribution-coverage.md` (changes the same panels' data later)

## Observed failure

On Window 30d both bar gauges show bars and values but no names. Both are `bargauge`, `h: 8`, `w: 6`, horizontal,
`namePlacement: top`, `minVizHeight: 8`, legends `{{repo}} {{mode}}` and `{{repo}}`.

## Root cause

The row count, not the layout. The 2026-10-25 fix sized the gauges for about six rows. The exporter names a
session's repo after its `cwd` basename, so one-off clones (`shopping-cart-frontend-nocache`,
`shopping-cart-frontend-tw4`, `k3d-manager-v1.41.0-wt`, ...) each get a row; 30d now holds about 20. At about 20 rows in
8 grid units Grafana has no height left for a name line above each bar and drops all names.

## Fix

1. Cap both panels at 8 rows: `topk(8, <current sum by ...>)` for the named rows, plus one `other` row that sums the
   rest (for example `sum(<current sum>) - sum(topk(8, <current sum>))` with legend `other`, hidden when it is 0).
2. Keep `h` large enough that 9 rows each keep their name line (raise `h` only if needed; keep the grid free of
   overlaps and gaps, shifting panels below if `h` changes).
3. Keep the metric names, label sets, `$window` selector, units and other options unchanged.

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`
- `scripts/tests/bin/test_dashboard_queries.py` (only if it pins these two exprs)
- `CHANGELOG.md`

## What NOT to do

- Do not normalise clone names to their repo in the exporter (out of scope; belongs to the cost-attribution plan).
- Do not change any other panel's query or options.
- Do not edit `scripts/tests/fixtures/agent-dispatch-dashboard-pre-split.yaml`.

## Acceptance

```yaml
must:
  M1: panels "Untracked by repo" and "Tokens by repo" each return at most 8 named series via topk(8, ...) over the existing sum, for window="$window"
  M2: each panel has an "other" series equal to the total minus the top 8, so the panel's sum still equals the original sum
  M3: each panel's height gives every row (8 named + other) its name line — at least 1 grid unit per 2 rows (h >= 5 for 9 rows) with namePlacement top kept
must_not:
  N1: no other panel's expr, unit or options change
  N2: no gridPos rectangles overlap and the dashboard JSON stays valid
  N3: the metric names and label sets (repo, mode, window) used by the two panels do not change
evidence:
  E1:
    proves: [M1, M2, M3, N1, N2, N3]
    kind: offline
    intent: >-
      You will see agent_dispatch_dashboard.bats find both panels by title, assert topk(8 in the named target and an
      "other" target built from the same sum, assert the height rule, and check no gridPos rectangles intersect;
      the topk and other assertions fail on the pre-fix file. make validate-manifests passes.
    what: bats scripts/tests/plugins/agent_dispatch_dashboard.bats; pytest scripts/tests/bin/test_dashboard_queries.py
  E2:
    proves: [M1, M3]
    kind: live
    intent: >-
      You will see, after the hub syncs the dashboard, Window 30d on both panels show at most 9 bars, each with its repo
      (and mode) name readable above it.
    what: operator screenshot of /d/k3dm-agent-activity, Window 30d
interface:
  - scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml (ConfigMap data key agent-activity.json)
  - Prometheus metrics k3dm_codex_untracked_sessions{window,repo,mode}, k3dm_codex_tokens{window,repo}
  - Grafana /d/k3dm-agent-activity
```
