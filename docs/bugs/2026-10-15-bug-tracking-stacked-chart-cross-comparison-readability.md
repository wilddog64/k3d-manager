# P3 — Bug Tracking stacked charts are hard to compare without visible values and legends

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.44.0` (triage 2026-10-15, operator-approved placement)
**Priority:** P3 — Grafana presentation/readability; no data-integrity defect established
**Status:** OPEN — operator screenshots reviewed, configuration inspected; implementation not started
**Approval:** operator explicitly requested P3 bug filing; no code or dashboard changes authorized

## Observed problem

Operator compared the two Grafana Bug Tracking panels, `Bugs filed per release, by priority` and `Bugs per release, open vs fixed`, for current release `v1.43.2`. Both display a total of roughly 36 bugs, but their stacked bars cannot be compared confidently at a glance. The same orange color represents **P2** in the priority chart and **open** in the state chart. The visible panels have no easily accessible legend or segment counts. The operator initially could not identify P3 in v1.43.2 even though it appears as the yellow section in the priority panel.

Screenshots (operator, 2026-10-15) show the panels individually and within the dashboard. The screenshot crops do **not** prove legends are completely absent: check whether they are merely below the visible area or clipped due to panel height, viewport, scrolling or dashboard layout. Likewise, the data appears consistent; **no incorrect bug classification/count is established**.

## Confirmed source configuration

`scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`:

- Both stacked panels query `sum by (release, order, priority/state) (k3dm_bug_release_docs) > 0`, formatted as instant tables, with `groupingToMatrix` transformations.
- Priority bar color overrides: P0 dark red, P1 red, P2 orange, P3 yellow, unset gray.
- Both panel configurations use `options.showValue: "never"`, so the plotted segments do not show counts.
- Both declare a legend at `placement: "bottom"` with `showLegend: true`; insufficient vertical space or cropping is a plausible reason the legends were not visible in the shared views, not a confirmed configuration omission.
- The state chart uses distinct labels (open/closed/unknown) and color choices; check actual field overrides and legend visibility before making changes.

## Expected behavior

An operator must be able to interpret **each chart independently** and compare the current release's priority distribution to its open/fixed distribution without guessing color meanings or manually correlating two unlabeled stacks. Preserve accurate counts, release order, role of priority versus state, and existing zero-segment suppression.

## Investigation and fix requirements

1. Reproduce at the real dashboard panel dimensions and compare with the operator screenshots. Determine whether legends are below the scroll/crop, clipped, too small, or genuinely invisible; document exact result.
2. Ensure priority and state meanings are immediately discoverable within each chart (visible legend, clear title/subtitle, sufficient panel height or layout). Color alone must not be the only signal.
3. Add readable exact values for nontrivial segments (via sensible `showValue` behavior or tooltip/table), without reintroducing the prior regression where zero-value labels pile up. Avoid visual clutter in thin segments.
4. Make total release counts easy to verify and compare across panels, for example with an aligned per-release summary/table (Release, P0, P1, P2, P3, unset, open, fixed, unknown), or an equivalent compact solution. Do not invent new classifications: priority and state are **independent dimensions**.
5. Consider color reuse across the charts explicitly: using orange for P2 and open is not mathematically incorrect, but without visible, distinct legends it misleads. Decide whether separate palettes or prominent labels provide the clearest solution.
6. Preserve Prometheus query correctness and dashboard performance. Do not alter `bug-tally.py`, metric semantics, or counters without independent evidence of a backend issue.
7. Keep chart accessibility and smaller displays in scope: charts must still be interpretable when one is viewed independently or when a panel is cropped.

## Acceptance / regression tests

- For `v1.43.2`, both charts clearly identify segments and values, and reconcile to the same per-release total where source metric data is identical.
- Priority P3 (yellow) is identifiable without guessing; orange in the other chart cannot be mistaken for P2.
- Operators can obtain exact per-priority and per-status counts without mentally estimating segment heights.
- Legends remain available at typical dashboard sizes and in individual expanded panels; provide visual verification.
- No overlapping labels, `0` labels, empty-category artifacts, fractional counts, or small-bar clutter; preserve zero-value suppression.
- Dashboard JSON/configuration tests confirm legends/value-display and metric compatibility; screenshots or visual tests verify render behavior.

## Related

- `docs/bugs/2026-10-10-bug-dashboard-no-layout-no-release-view.md` — prior P3 layout fix; includes regression history for stacked-bar zero labels. This report is a **new readability regression/gap**, not reopening its completed data/exporter fix.
- `docs/plans/v1.43.0-bug-priority-tracking.md` — original priority tracking design.
- `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` — source of truth for panel definitions.

**Implementation:** not started. This filing does not modify Grafana, Prometheus, bug metadata or any live infrastructure.
