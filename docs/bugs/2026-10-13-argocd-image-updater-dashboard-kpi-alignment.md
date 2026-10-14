# ArgoCD Apps & Image Updater Hub dashboard KPI cards misaligned

**Status:** OPEN — UI defect observed; fractional job metric requires investigation
**Priority:** P3
**Filed:** 2026-10-13, operator request
**Release:** v1.43.2 (triage; reschedule if release capacity is exhausted)
**Approval:** explicit operator request to file a P3 bug; no implementation authorized
**Component:** Grafana dashboard `ArgoCD Apps & Image Updater Hub` (locate its source ConfigMap before editing)

## Symptoms

Operator screenshots of the dashboard (last seven days / thirty-day KPI cards) show uneven, poorly aligned stat panels:
- `Image Updater Apps Watched`, `Images Updated (30d)`, and `Image Updater Errors (30d)` use inconsistent panel widths, heights, and visual placement despite being comparable KPIs.
- `App CVE Scan Successful Jobs` and `App CVE Scan Failed Jobs` appear in small, disjoint positions beneath larger KPI cards.
- Stat text and number sizes/centering are inconsistent, making the dashboard difficult to scan.
- `App CVE Scan Successful Jobs` displays **3.02**, a fractional figure for discrete completed jobs. This might be due to PromQL `increase()` extrapolation or an inappropriate metric/reduction; the query must be inspected before changing it. Do not assert a producer defect based only on the screenshot.

## Investigation

1. Identify the dashboard ConfigMap JSON and inventory stat panels' `gridPos`, value presentation, time overrides, queries, and field units.
2. Reproduce the uneven arrangement at the operator's normal desktop width. Ensure it also behaves sensibly on narrower views.
3. Inspect the successful/failed job queries and metric types. Determine whether fractional values are mathematically valid counter extrapolations rather than observed job counts. Choose a query/aggregation that truthfully reports the intended metric; never silently round away a semantic error.
4. Confirm which zero-valued KPIs represent a real zero versus missing samples; avoid converting `No data` to zero without evidence.

## Expected behavior

- Related Image Updater KPIs appear as a coherent, equal-height row/grid; CVE scan outcome KPIs are similarly grouped, aligned and legible.
- Numeric panels use consistent fonts, placement, units and precision; discrete **job counts** display meaningful whole-number counts derived from an appropriate metric.
- Existing panel titles, dashboards, variables, links and data sources remain intact. No changes to Image Updater, Trivy, CVE promotion or other production operations.

## Acceptance

- [ ] Before/after screenshots demonstrate aligned stat panels at desktop width and readable responsive layout.
- [ ] Dashboard JSON grid positions contain no unintended overlaps or awkward orphaned cards.
- [ ] `App CVE Scan Successful Jobs`'s `3.02` display is explained by the actual PromQL/metric semantics and corrected if necessary; compare against real Kubernetes Job history within retention limits.
- [ ] Other stat panels distinguish measured zero from missing data; successful and failed job counts use compatible time windows.
- [ ] Offline dashboard parse and existing Grafana/render tests pass; check PromQL where feasible.
- [ ] Live Grafana review verifies the cards and values without requiring cluster mutations.

## Files

Discover the actual `ArgoCD Apps & Image Updater Hub` dashboard source under `scripts/etc/` and related dashboard test files; update `CHANGELOG.md` if fixed. This report only files the issue.
