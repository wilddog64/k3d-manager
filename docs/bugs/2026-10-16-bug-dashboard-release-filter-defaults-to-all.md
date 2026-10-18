# Bug: Bug Tracking opens on All releases, and its table is not ordered by priority

**Status:** LIVE-VERIFIED — 2026-10-16: operator opened /d/k3dm-bugs with no URL parameters; Release = v1.43.4, rows P1 → P2 → P3, Verified fixes = Show all (fixed in df9c8e4c, spec `docs/plans/v1.43.4-bug-dashboard-defaults.md`)
**Fix commit:** `df9c8e4c`
**Live evidence:** 2026-10-16 · run operator-browser-k3dm-bugs · env hub/k3d · scenario dashboard-default-load · commit df9c8e4c · proves fix
**Priority:** P3
**Filed:** 2026-10-16
**Detected by:** human (operator)
**Affected:** `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`, variable `release`
**Branch:** `k3d-manager-v1.43.4`
**Approval:** explicit 2026-10-16 "is it possible default to current release … can do this in next
release" and "when filter with current release can we sort by priority" (operator);
item 3: explicit 2026-10-16 "go ahead" to Claude's offer to open with Verified fixes = All (operator)

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

Checked 2026-10-16: the sort is applied (`sortBy` runs before `organize`), and the live
`sort_key` for v1.43.2 is status-first (`… v1.43.2 0 P3 …` for open, `… 3 P2 …` for fixed), so
open P3s sort above fixed P1s by default. The operator's screenshot shows the requested order,
not the current default. Changing the key is the whole fix.

## Item 3: open with Verified fixes = Show all

The `verified` variable saves `current` = **Hide live-verified** (`^(false|-)?$`), set when the
Live-verified column was added in v1.43.2. On 2026-10-16 the operator reopened the dashboard and saw
one row for v1.43.3: the other seven bugs are live-verified, so the default hid them and the table
read as broken.

Fix: save `current` = `{"selected": true, "text": "Show all", "value": ".*"}`. Keep the query
`Hide live-verified : ^(false|-)?$,Show all : .*` and its option order, so hiding stays one click
away. Update the BATS assertion at `grafana_dashboard_bugs.bats:53` (`current.text == "Show all"`)
and the guide sentence at `docs/guides/grafana-dashboards.md:403` that calls Hide live-verified the
default.

## Proof

Open the dashboard with no URL parameters while on `k3d-manager-v1.43.4`: Release shows v1.43.4;
switching Repo to lib-foundation shows All with data. Verified fixes shows Show all, and v1.43.3 lists all 8 of its bugs. Bugs rows run P0 → P1 → P2 → P3 → unset within each release. A BATS test asserts the variable wiring with
`jq`, not whole lines.
