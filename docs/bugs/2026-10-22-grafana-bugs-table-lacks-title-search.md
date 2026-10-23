# Bug: k3dm Bug Tracking Bugs table has no title search or keyword filter

**Filed:** 2026-10-22
**Status:** OPEN — operator screenshot and dashboard configuration confirm usability gap; implementation not started
**Priority:** P3 — dashboard usability and bug discoverability
**Severity:** low
**Approval:** approved — operator, 2026-10-22: "go ahead" to dispatching to Luna
**Release:** v1.43.5 (bug; exempt from plan cap)
**Branch:** `k3d-manager-v1.43.5`
**Found by:** operator reviewing k3dm Bug Tracking dashboard at approximately 08:00 PDT, 2026-10-22
**Component:** `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`; bug-tracking dashboard variable/query tests and guide
**Related:** `docs/bugs/2026-10-21-firing-alerts-dashboard-missing-start-time-and-age.md`; `docs/plans/v1.43.2-bug-dashboard-release-filter.md`; `docs/bugs/2026-10-11-bug-dashboard-cannot-list-open-bugs.md`

## Symptom

The `k3dm Bug Tracking` dashboard `Bugs` table shows bug titles sorted
alphabetically (the arrow beside `Bug`), but does not provide a search/filter
control on bug title or filename. The operator is trying to find the reopened P3
`Firing Alerts by Category omits when alerts started firing and how long they have
been active` (file
`docs/bugs/2026-10-21-firing-alerts-dashboard-missing-start-time-and-age.md`).
The screenshot shows multiple `v1.43.5` bugs in the table, confirming the release
selection can display that release, but locating a specific bug requires manual
scrolling and alphabetic sorting. The table does not search by text.

This is **not** proof that the reopened bug's metrics were published: discovery,
repository synchronization, and telemetry ingestion remain separate checks.
Searching must not silently hide an ingestion failure by presenting an empty table
as proof that a bug does not exist.

## Current implementation

`scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` defines the
`Bugs` table with an instant Prometheus query:

```promql
k3dm_bug_info{repo="$repo",release=~"$release",live_verified=~"$verified"}
```

The existing dashboard variables are `repo`, `release`, and `verified`;
no title-search variable or visible query-string filter exists.
The exporter `bin/k3dm-vectordb-metrics` already emits labels `title`,
`bug` (filename stem), `priority`, `release`, `status` and `repo`
on `k3dm_bug_info`. A server-side title/filename search therefore should
not require a new exporter label or any new per-bug cardinality.

Note: `REOPENED` normalizes to `status="open"` in
`scripts/lib/hermes/prior_art.py`. This separate lifecycle limitation
does not prevent matching the title or filename.

## Expected behavior

Add an operator-friendly **Bug search** textbox near the existing dashboard
variables. It should filter the `Bugs` table by human-readable bug title and
ideally filename stem, without disturbing `repo`, `release`, or
`verified` selection. Empty search must mean *no text filter*, including when
a user clears the textbox. Search should be case-insensitive and support ordinary
substrings such as `firing alerts`, `grafana`, and `thread`.

The filter should support finding a reopened bug without requiring operators
to know its position in an alphabetically sorted list. Existing GitHub title
links must keep working.

## Fix (revised 2026-10-22, Claude review)

Use Grafana's built-in table column filter instead of a textbox variable. The
filter runs in the browser over rows the query already returned, so the PromQL
does not change and user input never reaches Prometheus. That removes the
regex-escaping risk the original proposal had to test around.

- **F1.** In the `Bugs` table panel of
  `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`, enable column
  filtering for the bug title column (and the filename `bug` column if shown):
  set `fieldConfig.defaults.custom.filterable: true`, or a field override for
  those columns only. Leave the query, variables, sort and links unchanged.
- **F2.** BATS assertion in `scripts/tests/plugins/grafana_dashboard_appsets.bats`:
  parse the dashboard JSON with `jq` and assert the `Bugs` panel's title column
  is filterable, and that the panel's PromQL `expr` still contains the
  `repo`, `release` and `live_verified` matchers. Assert on parsed fields, not
  whole source lines.
- **F3.** One paragraph in `docs/guides/grafana-dashboards.md`: the funnel icon
  on the Bug column header filters rows; an empty table with no filter set means
  no `k3dm_bug_info` series, not a missing bug (check ingestion).

**Fallback, only if the operator rejects the column filter:** a textbox
variable feeding PromQL. That needs the escaping tests the original filing
listed (empty, spaces, punctuation, regex characters) and is a separate change.

Grafana's column filter is a value picker with a search box, matching on the
displayed value. Confirm in E2 that it is usable for ~100 rows; if not, reopen
with the fallback.

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`
- `scripts/tests/plugins/grafana_dashboard_appsets.bats`
- `docs/guides/grafana-dashboards.md`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: The Bugs table's bug title column offers a column filter that narrows the rows to a chosen title, without manual scrolling.
  - id: M2
    text: Clearing the column filter restores all rows permitted by the repo, release and verified variables.
  - id: M3
    text: The Bugs panel query, the repo/release/verified variables, row sorting and GitHub bug links are unchanged.
must_not:
  - id: N1
    text: The Bugs title column must not be unfilterable (red on the pre-fix dashboard, where no column is filterable).
  - id: N2
    text: The Bugs PromQL must not lose its repo, release or live_verified matchers, and must not interpolate any new user-typed variable.
  - id: N3
    text: No new Prometheus metric or label is added.
evidence:
  - id: E1
    kind: offline
    proves: [M3, N1, N2, N3]
    text: bats scripts/tests/plugins/grafana_dashboard_appsets.bats parses the dashboard JSON with jq; N1 red on the pre-fix dashboard; a mutation that drops a matcher from the Bugs expr turns N2 red.
  - id: E2
    kind: live
    proves: [M1, M2, M3]
    text: After make platform-ops, the operator filters the Bug column on release v1.43.5 for the reopened firing-alerts bug and clears the filter; Claude reads the screenshots. If the bug is absent, check its k3dm_bug_info series before calling the filter broken.
interface:
  - scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml (Bugs table panel)
  - scripts/tests/plugins/grafana_dashboard_appsets.bats
  - docs/guides/grafana-dashboards.md
```

## Definition of Done

- [ ] F1–F3 on `k3d-manager-v1.43.5`; only the interface files above plus `CHANGELOG.md` change.
- [ ] N1 shown red against the pre-fix dashboard; `bats scripts/tests/plugins/grafana_dashboard_appsets.bats` green.
- [ ] Commit: `fix(grafana): make the Bugs table title column filterable`
- [ ] Operator separately approves implementation and verifies live behavior.
- [ ] Record fix SHA, evidence and final status transition in this bug.

## What NOT to Do

- Do NOT create a PR, merge to `main`, or modify implementation code as part of this filing.
- Do NOT sync or deploy Grafana/Prometheus while filing.
- Do NOT mistake absent telemetry for a search failure or claim that a search query repairs ingestion.
