# Bug: PR Checks "Checks per PR" ignores its sort order, so rows from different PRs interleave

**Status:** OPEN
**Priority:** P3
**Approval:** operator, 2026-10-30 ("go ahead to file a P3 bug")
**Filed:** 2026-10-30
**Detected by:** operator (read two open Dependabot PRs as duplicate rows)
**Affected:** `scripts/etc/argocd/platform-ops/grafana-dashboard-pr-checks.yaml` panel 6 **Checks per PR**
**Branch:** `k3d-manager-v1.43.12`
**Related:** `docs/bugs/2026-10-19-pr-checks-grafana-tables-misaligned-populated-state.md` (kept the same `sortBy` unchanged)

## Observed failure

`wilddog64/shopping-cart-payment` had two open PRs, #96 and #98. The table showed each check twice in
a row (API Compatibility 96, API Compatibility 98, Build and Test 96, Build and Test 98, ...), which
the operator read as duplicate rows. The rows are correct; their order is not.

## Root cause

The panel's intended order (Repo, then PR descending, then Check) is written as a `sortBy` key inside
the `organize` transformation's options. `organize` has no sort option (only `excludeByName`,
`indexByName` and `renameByName`), so Grafana drops the key without an error. The table panel's own
`options` has no `sortBy` either, so rows come out in join order, which groups by check.

## Fix

In panel 6:

1. Remove the `sortBy` key from the `organize` options.
2. Add `indexByName` to `organize` so the columns read **Repo**, **PR**, **Check**, **State**, **Duration**.
3. After `organize`, add a `sortBy` transformation sorting by **PR** descending. Rows sharing a PR
   keep the join's Check order.
4. Keep `noValue`, mappings, units and the empty-state text unchanged.

Update `scripts/tests/plugins/grafana_dashboard_pr_checks.bats` (the panel 6 test) and, if it names
the column order, `docs/guides/grafana-dashboards/k3dm-pr-checks.md`. Takes effect after
`make platform-ops`.

## Acceptance

```yaml
must:
  M1: Panel 6 sorts its rows by PR descending through a sortBy transformation placed after organize, so each PR's checks form one contiguous block.
  M2: Panel 6's columns are ordered Repo, PR, Check, State, Duration.
must_not:
  N1: No organize transformation in the PR Checks dashboard carries a sortBy key.
  N2: The empty-state text, value mappings and units of panel 6 are unchanged.
evidence:
  E1: {proves: [M1, M2, N1, N2], kind: offline, what: "bats scripts/tests/plugins/grafana_dashboard_pr_checks.bats; the M1 and N1 tests red on the pre-fix dashboard"}
  E2: {proves: [M1], kind: live, what: "after make platform-ops, with two open PRs in one repo, Checks per PR lists each PR's checks as one block; operator or Claude reads it"}
interface:
  - scripts/etc/argocd/platform-ops/grafana-dashboard-pr-checks.yaml (pr-checks.json panel 6)
```
