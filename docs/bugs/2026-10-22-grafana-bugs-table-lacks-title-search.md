# Bug: k3dm Bug Tracking Bugs table has no title search or keyword filter

**Filed:** 2026-10-22
**Status:** OPEN — operator screenshot and dashboard configuration confirm usability gap; implementation not started
**Priority:** P3 — dashboard usability and bug discoverability
**Severity:** low
**Approval:** operator explicitly requested filing a P3 bug on 2026-10-22; implementation not authorized
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

## Proposed fix / investigation

1. Add a Grafana textbox variable `bug_search` with an empty default.
   Explicitly test Grafana's actual escaping/interpolation for empty values,
   literal punctuation, spaces, and regex metacharacters before choosing the
   final PromQL. Do **not** assume a single suggested `${bug_search:regex}`
   pattern behaves correctly for all inputs.
2. Filter `k3dm_bug_info` against existing `title` and (preferably) `bug`
   labels, preserving the dashboard's current `repo`, `release`,
   `live_verified` predicates. If using PromQL regex matchers, escape user
   literals rather than allowing user-supplied regex execution or malformed
   queries; handle blank input as all titles.
3. Keep query and label cardinality bounded. Reuse existing exporter labels;
   no additional Prometheus metrics, time series, runtime scraping, or
   index-time mutation should be needed.
4. Verify the deployed dashboard behavior with a known matching bug, a
   nonmatching substring, the search cleared, and mixed-case/punctuation
   input. Confirm the bug appears when present in Prometheus and selected by
   the existing release/verified filters; differentiate missing metric data
   from search behavior.
5. Update the dashboard guide and targeted BATS tests. Include an integration-
   level or Grafana query evaluation test for empty/literal search behavior;
   testing only JSON snippets is insufficient.

## Acceptance

```yaml
must:
  - id: M1
    text: A visible Bug search textbox filters the Bugs table by case-insensitive title substring, without manual scrolling.
  - id: M2
    text: An empty or cleared textbox restores all rows otherwise permitted by the repo, release and verified filters.
  - id: M3
    text: The new filter preserves existing release/verified selectors, row sorting, GitHub bug links and metric cardinality.
  - id: M4
    text: Ordinary inputs containing spaces, punctuation and regex metacharacters do not break the PromQL query or accidentally behave as arbitrary regex.
  - id: M5
    text: The test suite and guide demonstrate finding the reopened Grafana Health & Firing Alerts bug and distinguish missing ingestion from a nonmatching search.
must_not:
  - id: N1
    text: Do not fabricate a bug result if Prometheus has no k3dm_bug_info series for the requested bug.
  - id: N2
    text: Do not remove or weaken repo, release or live-verified filters.
  - id: N3
    text: Do not introduce new unbounded Prometheus labels or use raw unsanitized textbox input as a regular expression.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, M5, N1, N2, N3]
    text: Dashboard config/PromQL and fixture tests cover empty search, mixed case, spaces, punctuation, literal regex characters, exact known match, unrelated match, and existing filters.
  - id: E2
    kind: live
    proves: [M1, M2, M3, M5, N1]
    text: After separately approved rollout, in live Grafana search for "firing alerts" on release v1.43.5, show matching result and GitHub link; clear textbox and verify original rows return; cross-check raw Prometheus metric availability if the target bug is absent.
interface:
  - scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml
  - scripts/tests/plugins/grafana_dashboard_appsets.bats
  - docs/guides/grafana-dashboards.md
  - existing Prometheus k3dm_bug_info labels
```

## Definition of Done

- [ ] Bug search control implemented with safe literal substring matching.
- [ ] Existing dashboard variables, ordering and links preserved.
- [ ] Focused tests prove blank search and known-title searches, not just JSON shape.
- [ ] Operator separately approves implementation and verifies live behavior.
- [ ] Record fix SHA, evidence and final status transition in this bug.

## What NOT to Do

- Do NOT create a PR, merge to `main`, or modify implementation code as part of this filing.
- Do NOT sync or deploy Grafana/Prometheus while filing.
- Do NOT mistake absent telemetry for a search failure or claim that a search query repairs ingestion.
