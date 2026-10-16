# Bug: the Agent Dispatch dashboard's "Landing success" panel always shows No data

**Filed:** 2026-10-11
**Branch:** `k3d-manager-v1.43.2`
**Status:** VERIFIED — Claude offline: tests green, new tests red on the old code, mutations red. Awaiting live proof. Was: IMPLEMENTED — landed `c3f01f89` (Codex, Claude verified: BATS 4/4, mutation red; promtool: new expr 0.8333 for 5 landed / 1 tests, old expr empty. Live proof waits for `make dispatch-metrics` (hub has no dispatch series since the rebuild).)
**Approval:** explicit 2026-10-11 "go ahead to file bug at v1.43.2"
**Priority:** P3 — the raw counts are on the same dashboard in "Land outcomes"
**Severity:** low — one stat panel is blank; no metric is wrong or lost

## Symptom

On the k3dm Agent Dispatch dashboard (window `7d`), "Landing success" shows **No data**, while
"Land outcomes" beside it shows landed 5, rebase 1, scope 0, tests 1 (operator screenshot,
2026-10-11).

## Root cause

The panel query (`scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml:33`) is:

```
k3dm_dispatch_land_attempts{window="$window",result="landed"}
  / sum(k3dm_dispatch_land_attempts{window="$window",result=~"landed|tests"})
```

The numerator keeps its labels (`job`, `result`, `window`); `sum()` drops all of them. PromQL binary
operators match series on identical label sets, so the division has no matching pair and returns an
empty vector. Confirmed against the hub's Prometheus on 2026-10-11:

| query | result |
|---|---|
| `k3dm_dispatch_land_attempts{window="7d"}` | landed 5, rebase 1, scope 0, tests 1 |
| the panel query above | `[]` |
| `sum(…{result="landed"}) / sum(…{result=~"landed\|tests"})` | `0.8333` |

Nothing tests the panel's expression, so the exporter test passed while the panel was dead.

## Fix

1. `grafana-dashboard-agent-dispatch.yaml`, panel id 2: wrap the numerator in `sum(...)`:
   `sum(k3dm_dispatch_land_attempts{window=\"$window\",result=\"landed\"}) / sum(k3dm_dispatch_land_attempts{window=\"$window\",result=~\"landed|tests\"})`.
   Nothing else in the panel changes (unit `percentunit`, red below 0.8).
2. `scripts/tests/plugins/agent_dispatch_dashboard.bats`: assert the Landing success expression's
   two sides are both aggregated — the numerator starts with `sum(` — so a bare-series numerator
   against an aggregated denominator is red.

## Files

| File | Change |
|---|---|
| `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml` | Fix 1 |
| `scripts/tests/plugins/agent_dispatch_dashboard.bats` | Fix 2 |
| `CHANGELOG.md` | `[Unreleased]` → `### Fixed` entry |

## Tests

- The new BATS assertion is red against the current dashboard and green after the fix.
- Mutation: remove the numerator's `sum(` → the assertion is red.

## Proof it works

After `make appsets-reapply` on the release branch, the panel reads about 83% for the 7d window
(5 landed / 6 integration results) instead of No data.

## What NOT to Do

- Do NOT count `rebase` or `scope` in the denominator; the panel description excludes them on
  purpose.
- Do NOT use `ignoring(result)` on the bare numerator instead; `sum` on both sides is the form that
  survives an added label (e.g. `instance`).
