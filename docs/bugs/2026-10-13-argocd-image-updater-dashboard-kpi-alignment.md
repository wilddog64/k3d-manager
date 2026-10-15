# Bug: ArgoCD Apps & Image Updater Hub dashboard KPI cards misaligned

**Status:** OPEN — UI defect observed; fractional job metric requires investigation
**Branch:** unscheduled P3 backlog (triage 2026-10-15, operator-approved placement)
**Priority:** P3
**Filed:** 2026-10-13, operator request
**Release:** unscheduled (triage 2026-10-15, operator-approved placement)
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

## Explicit investigation: fractional successful Job count (3.02)

The operator explicitly requests that the observed **3.02 successful jobs in 30 days** be investigated, not merely reformatted. Kubernetes completed Jobs are discrete; a fractional display must be reconciled with the precise metric and query semantics.

- Copy the panel's exact PromQL, Grafana reducer/calculation, query range and override. Identify its source metric type (counter, gauge, kube-state-metrics series, or recording rule).
- If the expression uses `increase(...[30d])`, determine whether scrape extrapolation and/or sparse samples produce the fractional output. If it uses `sum`, check whether multiple labeled series or duplicated jobs are aggregated unexpectedly.
- Compare the query with actual successful Job transitions in the same available time window, accounting for completed-job deletion, retention, and missing history. Do not interpret unavailable historical evidence as zero successful jobs.
- Decide whether the panel should report an **observed integer event count**, an **estimated counter increase**, or another quantity; use a title and precision matching its actual semantics. Do not simply apply `round()` until the source and aggregation are validated.
- Validate that success and failure panels use compatible counting rules, job selectors and 30-day windows; add an offline PromQL/dashboard regression test where practical.

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
