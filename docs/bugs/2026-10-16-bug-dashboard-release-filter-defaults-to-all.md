# Bug: Bug Tracking opens on All releases, and its table is not ordered by priority

**Status:** OPEN — not started
**Priority:** P3
**Filed:** 2026-10-16
**Detected by:** human (operator)
**Affected:** `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`, variable `release`
**Branch:** `k3d-manager-v1.43.4`
**Approval:** explicit 2026-10-16 "is it possible default to current release … can do this in next
release" and "when filter with current release can we sort by priority" (operator)

## Problem

The k3dm Bug Tracking dashboard opens with **Release (filed in) = All**. The operator usually wants
the release in progress. Today the variable is a multi-select query
`label_values(k3dm_bug_info{repo="$repo"}, release_order)` with a saved `current` of `$__all`.

## Constraint

Grafana cannot set a variable's default from a query result; `current` in the JSON is static. A
hard-coded release would go stale every release.

## Proposed approach (to confirm in the spec)

- Source: `k3dm_bug_current_release_info{repo,release}`, already published for k3d-manager
  (`bin/k3dm-vectordb-metrics`), never for lib-foundation.
- Make the current release the **first** option and save a `current` that matches no option, so
  Grafana falls back to the first option on load. Keep **All** selectable.
- lib-foundation, or k3d-manager with no `current_release_info`: fall back to All, not an empty
  dashboard.
- Alternative if the fallback proves unreliable in our Grafana version: a dashboard link /
  Hermes link that passes `var-release=<current>` in the URL, keeping All as the JSON default.

## Item 2: order the Bugs table by priority within a release

The table sorts on the hidden `sort_key` label built in `bin/k3dm-vectordb-metrics`:
`{release_order} {STATUS_RANK[status]} {priority} {filed} {stem}`. Status ranks ahead of priority, so
within one release a Fixed P3 can sit above an open P2. Reorder the key to
`{release_order} {priority} {STATUS_RANK[status]} {filed} {stem}`. P0 sorts first, and `unset`
sorts after P3 because "unset" > "P3" in byte order; assert that in a test. With All releases
selected, rows still group by release first. The column header stays sortable by hand.

Check first: the operator's 2026-10-16 screenshot of v1.43.2 shows Fixed P1/P2 rows above Open P3
rows, which a status-first key would not produce. `organize` excludes `sort_key` before the
table's `sortBy` can use it, so the sort may not be applied at all and the visible order may come
from the series order. Confirm in Grafana which one holds. If the sort is not applied, sort with a
`sortBy` transformation **before** `organize`.

## Proof

Open the dashboard with no URL parameters while on `k3d-manager-v1.43.4`: Release shows v1.43.4;
switching Repo to lib-foundation shows All with data. Bugs rows run P0 → P1 → P2 → P3 → unset within each release. A BATS test asserts the variable wiring with
`jq`, not whole lines.
