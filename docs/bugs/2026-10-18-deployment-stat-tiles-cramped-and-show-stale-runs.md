# Bug: deployment dashboard stat tiles are cramped and show runs the Pushgateway no longer holds

**Filed:** 2026-10-18 (Claude, from the operator's dashboard screenshots after the E3 `make up` / `make down`)
**Status:** FIXED — Claude 2026-10-18, verified offline; live check after the next `make platform-ops`
**Priority:** P3 — cosmetic and misleading tiles; the underlying series are correct
**Severity:** low
**Approval:** approved — operator, 2026-10-18: "go ahead"
**Branch:** `k3d-manager-v1.43.5`
**Release:** v1.43.5
**Component:** `scripts/etc/grafana/dashboards/k3dm-deployments-configmap.yaml`,
`scripts/tests/plugins/observability_deployment_dashboard.bats`

## Symptom

On **k3dm Deployment Metrics** (Last 24 hours), after a real `up/aws` and `down/aws`:

- **Cramped labels.** All four stat tiles lay their values side by side. `down/somethingelse` ran into
  `up/aws` in "Last Deployment Time" and was cut to `down/somethinge…` in "Last Deployment Success";
  "36 minutes ago" wrapped onto two lines, and wrapped names knocked the values out of line.
- **Stale runs.** "Last acg-down Duration" showed `aws (failed) 0 s` beside the real
  `aws (success) 2.12 mins`, and the `somethingelse` series from a test leak stayed on every tile,
  although the Pushgateway no longer held them.
- **Lag.** The tiles still showed the old `down/aws FAILED` after the graph already had the new
  `down/aws (success)` point.

## Root cause

1. `orientation: auto` puts multiple values in columns in a wide, short tile.
2. The stat targets are range queries reduced with `lastNotNull` over the dashboard range. A series
   that was deleted from the Pushgateway keeps its last value in the TSDB, so a tile shows it for up to
   24 h. A narrow tile also gets a coarse step, so its last point can be minutes older than the graph's.
3. The duration tiles group `by (provider, status)`. A Pushgateway group keeps one status at a time,
   but the TSDB keeps both series, so an old failure stays next to a newer success.

## Fix (applied)

- The four stat targets are instant queries (`"instant": true, "range": false`): each tile shows what
  the Pushgateway holds now.
- `orientation: horizontal`, `textMode: value_and_name`: one row per series, name left, value right.
- The duration tiles group `by (provider)` with legend `{{provider}}`; status stays on
  "Last Deployment Success".
- "Deployment Duration Over Time" is unchanged; history is its purpose.

## Acceptance

```yaml
must:
  - id: M1
    text: Every stat panel's target is an instant query.
  - id: M2
    text: Every stat panel has orientation horizontal and textMode value_and_name.
  - id: M3
    text: The duration stat panels do not group or label by status.
must_not:
  - id: N1
    text: The timeseries panel must not become an instant query (it must keep history).
  - id: N2
    text: A series deleted from the Pushgateway must not stay on a stat tile for the dashboard range (red on pre-fix, which uses range queries).
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    text: bats scripts/tests/plugins/observability_deployment_dashboard.bats — new test green on the fix, red on the pre-fix dashboard.
  - id: E2
    proves: [M1, M2, M3, N2]
    kind: live
    text: after make platform-ops, the hub dashboard tiles show only up/aws and down/aws, one per row, with no somethingelse and no aws (failed).
interface:
  - scripts/etc/grafana/dashboards/k3dm-deployments-configmap.yaml (dashboard JSON)
  - make platform-ops (deploys it to the hub)
```

## Verification (Claude, 2026-10-18)

- E1: `observability_deployment_dashboard.bats` 3/3 and `deployment_metrics.bats` 8/8 green. The new
  test fails on a copy of the pre-fix dashboard in a scratch tree ("not an instant query").
- E2: pending the operator's `make platform-ops`.
