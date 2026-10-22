# Bug: E2E failure tables lack consistent filtering and run/time correlation (2026-10-21)

**Status:** VERIFIED — offline tests passed; live Grafana verification pending
**Priority:** P3 — observability usability / audit correlation, no evidence of test execution failure
**Release:** v1.43.5
**Branch:** `k3d-manager-v1.43.5`
**Dispatch approval:** operator requested review and dispatch of current-release P3 bugs, 2026-10-22
**Filed:** 2026-10-21, at operator request
**Approval:** operator requested "go ahead to file P3" for the Recent runs / Failure groups / Failure details discrepancy, with established instruction to commit directly to current release branch and no PR
**Component:** E2E Verification Grafana dashboard, E2E result exporter/metrics
**Related:** `docs/bugs/2026-10-16-e2e-setup-failure-invisible-in-failure-panels.md` (different, live-verified failure-group production bug); `docs/guides/grafana-dashboards/e2e-verification.md`
**Evidence:** 2026-10-21 operator screenshot; read-only inspection of `scripts/etc/argocd/platform-ops/grafana-dashboard-e2e.yaml` at current release branch. No live query was run.

## Observation

The operator cannot reliably tell whether **Recent runs**, **Failure groups**, and **Failure details** refer to the same run/time window. The screenshot shows six matching Stripe/payment run IDs in the Recent runs and Failure details tables, while Failure groups contains additional run IDs not visible in the eight displayed Recent runs rows. Recent runs exposes `Run date` and `Status now` (e.g. `fixed: passed ...`), while both failure tables expose neither run date nor current resolution status. The latter continue to show historical failed assertions for runs whose matching suite later passed; retained historical evidence is expected, not itself a defect.

Examples matching across screenshot panels:
- `1792201944-27199`, `1792203807-7042`, `1792204737-19253`
- `1792235987-31168`, `1792236389-10503`, `1792239012-26194`

Failure groups additionally shows `1792235425-21547` (aborted at checking-hub-apps) and `1792372702-6827` (aborted at provisioning-sandbox), not visible among the eight screenshot Recent runs rows. **Not proof of data loss or time misfiltering:** table pagination/visible rows, filters, limits and retention must be accounted for first.

## Confirmed source-level discrepancy

`scripts/etc/argocd/platform-ops/grafana-dashboard-e2e.yaml` currently defines:

| Panel | Instant PromQL | Label filters |
|---|---|---|
| Recent runs | `topk(100, e2e_run_info{...,failure_ratio=~".*%.*"})` | `exported_service`, `tier`, `runner` plus `failure_ratio` |
| Failure groups | `topk(200, e2e_failure_group_info{...})` | `tier`, `runner` only |
| Failure details | `topk(100, e2e_failure_info{...})` | `tier`, `runner` only |

The failure panels omit the `$service` variable that Recent runs applies. All are **instant** queries; the dashboard time picker does not imply these panels enumerate historical events created only within the selected range. The metric series are bounded independently, so their displayed run-ID sets need not match. Failure tables do not display a run timestamp, and there is no dashboard-wide Run ID drill-down. Query labels use `exported_service` with ownership semantics that may differ for consolidated runs; simply adding the Recent runs service filter could hide relevant failures and must be tested before implementation.

## Expected behavior / requirements

1. **Explicit temporal semantics:** Document how the time picker, instant queries, metric staleness/retention and per-panel caps interact. Decide whether all three panels should show *runs in the selected event-time range* or clearly label them as the latest *retained* runs/failures. Do not assert time filtering is broken until a controlled live query establishes it.
2. **Correlation timestamp:** Add a consistently formatted `Run date (UTC)` to Failure groups and Failure details, sourced from the owning run's actual event timestamp, not exporter scrape time. Missing provenance must be N/A rather than a fabricated date.
3. **Current resolution context:** Display `Status now` (or an unambiguous equivalent) for historical failure groups/details, derived consistently with Recent runs' matching dimensions `tier/service/project/runner` and later passing run logic. Do not overwrite the original failure result.
4. **Filtering parity without data loss:** Align dashboard `service`, `tier`, and `runner` selections across panels using the correct per-failure *owning service* versus consolidated run service semantics. Validate cross-service, payment and setup-aborted examples before applying additional filters.
5. **Run ID correlation:** Provide an accessible way to restrict or navigate the three panels for an exact `run_id` (e.g., templated variable or data link), without changing the underlying run IDs or test events.
6. **Deterministic ordering/limits:** Preserve bounded queries and browser responsiveness, make row limits and sorting apparent, and avoid claiming that different numbers of rows indicate discrepancies where source metrics legitimately have different cardinalities.
7. **Historical audit truth:** Old failing test rows may remain when `Status now` is `fixed: passed <date>`; retain original failing assertions, identify the subsequent matching successful run, and do not imply that the failed run itself passed.

## Investigation and implementation scope

- Inspect `scripts/etc/argocd/platform-ops/grafana-dashboard-e2e.yaml`, `scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml` and `docs/guides/grafana-dashboards/e2e-verification.md`.
- Find current E2E dashboard/exporter regression tests (including `scripts/tests/plugins/e2e_observability.bats`) before editing. Prefer safe dashboard-only changes where existing bounded metric labels already provide required metadata; explicitly scope exporter changes if timestamp/status correlation is absent.
- Verify Grafana variables and PromQL label matching against representative historical/ongoing event examples; do not introduce high-cardinality unbounded queries or assume cross-service run labels equal failure owner labels.
- Do not alter E2E execution behavior, test outcomes, runtime clusters, or historical ConfigMaps to address a presentation concern.

## Tests / acceptance criteria

- [ ] Automated dashboard query/variable tests verify selected service/tier/runner and exact Run ID behavior for all three tables, including a consolidated run with a payment-owned failure and aborted sandbox runs.
- [ ] Failure groups and details show the same source run date (UTC) as Recent runs for a matched ID, not a scrape timestamp; missing timestamps show unknown/N/A.
- [ ] For an old failed run followed by a matching passing run, Recent runs and correlated failure rows display the same current resolution context without erasing the original assertion evidence.
- [ ] An old failed run without a later matching pass is not incorrectly marked fixed by an unrelated tier, runner, service, or project.
- [ ] Time selection behavior is documented and, if event-time filtering is implemented, demonstrably consistent across panels with matching event timestamps and explicit caps.
- [ ] Sorting, existing table fields, alert metrics and performance remain functional; tests cover no-data, legacy records, service ownership and cap boundaries.
- [ ] Live verification on Grafana compares the three panels under the same variables/time selection using at least one run ID appearing in all panels; capture actual queries and results before marking LIVE-VERIFIED.

## Definition of Done

- [ ] Source-level mismatch resolved or explicitly justified with clear UI semantics.
- [ ] Run timestamps and resolution status are available alongside failures, and run-ID cross-panel triage is usable.
- [ ] Offline tests pass with evidence recorded; perform separate operator-approved live verification before marking live-verified.
- [ ] Update dashboard documentation and relevant changelog as part of the eventual fix.
- [ ] Keep live Grafana verification, deployment, exporter restart, and runtime changes separate from the offline implementation dispatch.

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-e2e.yaml`
- `scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml`
- `scripts/tests/plugins/e2e_observability.bats`
- `docs/guides/grafana-dashboards/e2e-verification.md`

## Verification (2026-10-22)

Landed as `73819c18`. `bats scripts/tests/plugins/e2e_observability.bats` passed 26 tests; two Prometheus-rule tests were skipped because `promtool` is not installed. `shellcheck -x scripts/tests/plugins/e2e_observability.bats`, `_agent_lint`, `_agent_audit`, `make check-doc-links` (2310 files), and `git diff --check` passed. Live Grafana verification remains pending; this is not LIVE-VERIFIED.
