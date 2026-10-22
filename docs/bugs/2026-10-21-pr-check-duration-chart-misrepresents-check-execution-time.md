# Bug: PR Checks duration chart repeats completed runs across scrape timestamps

**Filed:** 2026-10-21 (operator screenshot; repository review)
**Status:** OPEN — diagnosis confirmed in source; live remediation not yet verified
**Priority:** P3 — misleading observability visualization; check status and collection remain functional
**Severity:** low
**Approval:** operator explicitly requested filing a P3 bug on 2026-10-21; implementation not yet approved
**Dispatch approval:** operator requested review and dispatch of current-release P3 bugs, 2026-10-22
**Release:** v1.43.5 (bug; exempt from plan cap)
**Branch:** `k3d-manager-v1.43.5`
**Component:** `scripts/etc/argocd/platform-ops/grafana-dashboard-pr-checks.yaml`, `scripts/lib/hermes/pr_checks.py`, corresponding PR-check tests and dashboard guide
**Related:** `docs/plans/v1.43.3-pr-checks-dashboard.md`, `docs/bugs/2026-10-18-pr-checks-dashboard-empty-tables-read-as-no-data.md`
**Found by:** operator, Grafana screenshot 2026-10-21 approximately 13:35 PDT

## Problem

The **k3dm PR Checks** dashboard's **Checks per PR** table (panel 6) shows each check's current
state and duration. Its **Check duration** time-series panel (panel 8) draws nearly horizontal
lines over October 20–21 for completed GitHub checks, making it appear that durations were
measured repeatedly throughout this period, or that checks ran continuously.

The operator asked whether the checks listed above actually executed at the times shown on
the duration chart. The graph does **not** establish that. Its x-axis represents Prometheus
sample timestamps rather than GitHub's check `started_at` or `completed_at`.

Screenshot examples: `shopping-cart-product-catalog` PR #62 has check durations of 2 s
(GitGuardian), 32 s (Lint & Type), and 51 s (Integration Test — Schema Self-Heal);
`shopping-cart-basket` PR #56 has a 25 s lint check. Panel 8 shows flat series
spanning a long time window. `GitHub read` reports `ok`.

## Source-level diagnosis

On `k3d-manager-v1.43.5`:

1. `scripts/lib/hermes/pr_checks.py` `collect()` retains GitHub check
   `started_at` and `completed_at` as epoch seconds, but `render()` emits only
   `k3dm_pr_check_duration_seconds{repo,pr,check}` as a duration value, with no
   completion-time metric.
2. Hermes republishes metrics for still-open PRs on later polls. A completed run's
   duration does not change, so Prometheus repeatedly observes that same value.
3. `scripts/etc/argocd/platform-ops/grafana-dashboard-pr-checks.yaml` panel 8 queries
   `k3dm_pr_check_duration_seconds{repo=~"$repo"}` as a standard range series without
   distinguishing samples from distinct GitHub check executions.
4. Panel 6 uses an *instant* query of the same duration metric for its table; that is
   appropriate for current-state display and should not be broken by the fix.

This is a semantics/presentation bug, not evidence that GitHub re-ran checks or that
the exporter failed. The screenshot alone does not prove when the individual checks ran;
compare actual GitHub timestamps to confirm live behavior.

## Expected behavior

The dashboard clearly distinguishes **actual GitHub check execution/completion time**
from **Hermes collection / Prometheus sample time**. If a chart is labeled as run
durations over time, it must put a completed check at its actual execution/completion
timestamp (or clearly disclose any intentional polling-based approximation). It must
not imply a new run at every scrape. The table should retain the latest current-state
view with accurate state and duration.

## Proposed investigation and fix scope

- Evaluate a bounded completion-time metric (for example,
  `k3dm_pr_check_completed_timestamp_seconds{repo,pr,check}`) using the GitHub
  timestamp already available to `collect()`. Consider whether a stable check-run ID
  is needed to distinguish reruns, and its cardinality/lifecycle implications, before
  adding it as a Prometheus label.
- Determine a suitable event-oriented Grafana representation or explicit
  **latest duration, sampled over time** label. A completion-time metric alone
  does not make ordinary range samples into execution events.
- Preserve the current panel 6 instant table and avoid confusing actively running
  checks (whose duration grows) with completed runs.
- Verify metric staleness/cleanup when PRs close, scraper failure behavior, and
  Grafana time-range edge cases. Avoid unbounded check-run series or false events.
- Add targeted collector and dashboard regression tests and update
  `docs/guides/grafana-dashboards.md` to explain timestamp semantics.

## Acceptance

```yaml
must:
  - id: M1
    text: PR Checks makes GitHub check completion timestamps distinguishable from Prometheus scrape timestamps.
  - id: M2
    text: The duration visualization either plots actual execution events at grounded GitHub timestamps or is explicitly labeled as a sampled latest-duration gauge without implying run frequency.
  - id: M3
    text: Checks per PR retains correct current state and duration, including in-progress and completed checks.
  - id: M4
    text: Closed PRs and repeated polls do not create uncontrolled series cardinality or fictitious new run events.
must_not:
  - id: N1
    text: A completed check is represented as multiple distinct executions solely because Hermes polls again.
  - id: N2
    text: The fix alters PR check conclusions, the existing collection health panels, or deploys directly to a cluster.
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2]
    kind: offline
    text: Fixture with a completed GitHub check and several later Hermes polls; validate emitted timestamps, Grafana target semantics, bounded labels and unchanged table values; demonstrate misleading pre-fix behavior.
  - id: E2
    proves: [M1, M2, M3, N1]
    kind: live
    text: After separately approved implementation and dashboard sync, compare one PR check's GitHub started_at/completed_at with chart position and table duration while subsequent Hermes polls occur.
interface:
  - scripts/lib/hermes/pr_checks.py (collector and Prometheus metrics)
  - scripts/etc/argocd/platform-ops/grafana-dashboard-pr-checks.yaml (panel 8; preserve panel 6)
  - scripts/tests/plugins/grafana_dashboard_pr_checks.bats and relevant Python collector tests
  - docs/guides/grafana-dashboards.md

## Files

- `scripts/lib/hermes/pr_checks.py`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-pr-checks.yaml`
- `scripts/tests/hermes/test_pr_checks.py`
- `scripts/tests/plugins/grafana_dashboard_pr_checks.bats`
- `docs/guides/grafana-dashboards/k3dm-pr-checks.md`
```

## Definition of Done

- [ ] Identify actual check timestamps on a reproducible PR and record the discrepancy.
- [ ] Proposed visualization/metrics contract meets M1–M4 and avoids N1–N2.
- [ ] Offline regression tests pass, including proof that the original behavior is caught.
- [ ] Operator approves the fix separately; complete live verification E2 and attach evidence.
- [ ] Update status, fix SHA, verification metadata, and dashboard documentation.

## What NOT to Do

- Do NOT create a PR or merge into `main`.
- Do NOT change code or deploy a dashboard as part of this filing.
- Do NOT assume the horizontal traces mean GitHub ran a check continuously.
- Do NOT add an unbounded run-ID label or equate a scrape timestamp with completion time.
