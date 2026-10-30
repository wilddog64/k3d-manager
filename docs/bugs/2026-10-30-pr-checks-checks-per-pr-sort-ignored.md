# Bug: PR Checks "Checks per PR" ignores its sort order, so rows from different PRs interleave

**Status:** OPEN — dispatched to Luna (`gpt-6-luna`) 2026-10-30, slug `pr-checks-sort`
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

**As landed (Claude's review amendment, 2026-10-30).** Luna placed a `sortBy` transformation after
`organize` on the PR column (panel 6) and on Repo then PR (panel 5). Claude changed both panels to
sort on the hidden `__join` key (`repo:pr:check`, or `repo:pr` on panel 5), ascending, placed
**before** `organize`, since `organize` hides that column. One key keeps each repo's PRs, and each
PR's checks, together. A PR-only sort mixes PRs that share a number across repos, and sorting on the
renamed columns depends on more than one key being honoured. PRs within a repo sort as strings
(ascending), not as numbers descending. Panel 5 also changed, despite "no other panel" below,
because it carried the same ignored `sortBy` and N1 covers every `organize` transformation.

Update `scripts/tests/plugins/grafana_dashboard_pr_checks.bats` (the panel 6 test) and, if it names
the column order, `docs/guides/grafana-dashboards/k3dm-pr-checks.md`. Takes effect after
`make platform-ops`.

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-pr-checks.yaml`
- `scripts/tests/plugins/grafana_dashboard_pr_checks.bats`
- `docs/guides/grafana-dashboards/k3dm-pr-checks.md` (only if it names the column order)
- `CHANGELOG.md` (one `### Fixed` line under `[Unreleased]`)

## What NOT to do

- Do not change any other panel, query, mapping, unit or empty-state text.
- Do not run `make platform-ops`, `kubectl` or anything against a cluster; the live check (E2) is the operator's or Claude's.
- Do not create a PR, commit to `main`, or skip hooks with `--no-verify`.
- Write the M1 and N1 tests first and show them red against the pre-fix dashboard on a temp copy.

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
