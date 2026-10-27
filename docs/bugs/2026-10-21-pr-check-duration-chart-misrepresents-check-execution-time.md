# Bug: PR Checks duration chart repeats completed runs across scrape timestamps

**Filed:** 2026-10-21 (operator screenshot; repository review)
**Status:** REOPENED — 2026-10-27 operator evidence of remaining current-versus-history inconsistency; previous offline tests passed, live acceptance pending
**Priority:** P3 — misleading observability visualization; check status and collection remain functional
**Severity:** low
**Approval:** operator explicitly requested filing a P3 bug on 2026-10-21; implementation not yet approved
**Dispatch approval:** operator requested review and dispatch of current-release P3 bugs, 2026-10-22
**Release:** v1.43.9 (reopened follow-up; originally filed against v1.43.5; bug exempt from plan cap)
**Branch:** `k3d-manager-v1.43.9`
**Component:** `scripts/etc/argocd/platform-ops/grafana-dashboard-pr-checks.yaml`, `scripts/lib/hermes/pr_checks.py`, corresponding PR-check tests and dashboard guide
**Related:** `docs/plans/v1.43.3-pr-checks-dashboard.md`, `docs/bugs/2026-10-18-pr-checks-dashboard-empty-tables-read-as-no-data.md`, `docs/plans/v1.45.2-pr-lifecycle-history-and-merge-visibility.md`
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

## Verification (2026-10-22)

Landed as `b77a4093`. `python3 -m pytest -q -p no:cacheprovider scripts/tests/hermes/test_pr_checks.py` passed 2/2; `bats scripts/tests/plugins/grafana_dashboard_pr_checks.bats` passed 5/5; ShellCheck, `_agent_lint`, `_agent_audit`, and `git diff --check` passed. Live verification remains pending; this is not LIVE-VERIFIED.
- `docs/guides/grafana-dashboards/k3dm-pr-checks.md`
```

## Reopened scope — current-versus-historical visibility mismatch (2026-10-27)

**Release history:** Originally filed and partially corrected in v1.43.5 (fix `b77a4093`, offline-verified). The newly observed operator-visible mismatch is reopened for v1.43.9, the active branch. The original fix history remains intact; the new regression must be independently verified before closure.

**Operator evidence:** Screenshots captured 2026-10-27 around 10:24–10:28 PDT:
- `wilddog64/shopping-cart-payment`: Open PRs = 0, Failing = 0 and Checks per PR = "No open PRs — no checks to show"; the 12-hour **Latest check duration (sampled)** panel still displays older #93/#94 series.
- `wilddog64/shopping-cart-frontend`: Open PRs = 0 and Checks per PR empty, but 24-hour duration history shows #133/#134 sampled checks.
- `wilddog64/k3d-manager`, `wilddog64/lib-foundation`, `wilddog64/shopping-cart-infra` and `wilddog64/shopping-cart-e2e-tests`: Open PRs = 0 and no duration data in the selected 24-hour period; GitHub read shows `ok` in the provided screenshots.
- Repo filter **All** joins any historical PR-duration samples matching the selected range, while repository-specific filters expose only their own matching series. Different repository results do not, by themselves, indicate a collector failure.

### Confirmed repository implementation, separate from live hypotheses

- `scripts/lib/hermes/pr_checks.py:collect()` requests `/repos/{repo}/pulls?state=open&per_page=20` and reads head check runs only for returned open PRs. `render()` always exports per-repo `k3dm_pr_checks_open_prs`, last-scrape timestamp and success on good reads; it emits PR/check duration metrics only for open PRs.
- Dashboard panels 5 and 6 use **instant queries** for current open PR details and check state; panel 8 uses a **range query** on `k3dm_pr_check_duration_seconds{repo=~"$repo"}`. Grafana `repo` is populated from `label_values(k3dm_pr_checks_open_prs, repo)`, which includes a repo with zero open PRs; All expands to `.*`.
- Prometheus retains earlier samples until history retention expires, so closed PR check durations can appear in panel 8 after disappearing from the instant tables. A long horizontal trace is **not** evidence that GitHub ran the CI job repeatedly or continuously.
- Current `GitHub read = ok` indicates that collector read succeeded; it does not mean each repository had an open PR or in-range duration sample. Empty historical series are distinct from read failures.
- Prior fix `b77a4093` added a check-completion timestamp metric and clarified the sampled panel label, with offline tests passing. It did **not** resolve the operator-visible semantic disconnect among current tables, historical duration traces and absence of current PRs. Do not misstate the previous fix as failed or live-verified.

### Required follow-up behavior

1. Preserve PR-duration history and existing current Open PRs counts. Do **not** filter away historical series merely to make panel 8 appear consistent with the current tables.
2. Make current-versus-historical panel semantics obvious: e.g. "Historical sampled check durations (may include now-closed PRs)", explain that time axis is scrape time, and mark earlier PR series as historical if their current PR is closed. If a per-series open/closed label cannot be established without new authoritative PR lifecycle collection, use honest panel-level annotation instead of guessing.
3. Distinguish **no open PRs**, **no historical check samples for the selected range**, and **GitHub read failed/stale** through panel descriptions or unambiguous empty-state presentation. An absent duration sample must never imply a failed collector or that no historical PR existed outside the range.
4. Verify All and each repo filter with fixtures containing: (a) currently open PR, (b) merged/closed PR with retained historical samples, (c) repo with no PR and no in-range samples, and (d) GitHub read failed with stale last-known samples. Ensure no misleading zero or fabricated success.
5. Verify a real GitHub check `started_at`/`completed_at`, Prometheus sample timestamps, and Grafana chart/table results in an operator live check; leave **Live verified = false** until evidenced.
6. Keep durable merged/closed PR history **out of this bug's fix**: that larger capability belongs to v1.45.2 `pr-lifecycle-history-and-merge-visibility`. This P3 targets clarity and correctness of the **existing** chart and table, without a new backend or additional plan slot.

### Follow-up acceptance

```yaml
must:
  - id: M5
    text: With zero current open PRs and retained earlier check samples, the dashboard clearly identifies the duration chart as historical and non-current without discarding samples.
  - id: M6
    text: With no in-range samples, the dashboard distinguishes normal absence of historical activity from a stale or failed GitHub read.
  - id: M7
    text: Repo=All and repo-specific filters use consistent documented time and repository semantics.
must_not:
  - id: N3
    text: Historical check series must not be removed just to match the open-PR instant tables.
  - id: N4
    text: A successful GitHub read, empty current PR set or a sampled-duration line must not be presented as proof of merge, continuous execution or live verification.
evidence:
  - id: E3
    kind: offline
    proves: [M5, M6, M7, N3, N4]
    text: Mixed current/open and historical/closed PR fixture, per-repo/All filters, empty-range and failed-read cases; old misleading presentation demonstrably fails.
  - id: E4
    kind: live
    proves: [M5, M6, M7]
    text: Operator screenshots showing one repo with 0 open PRs and historical checks, another with 0 and no samples, and a healthy GitHub read, cross-checked with actual GitHub completion times.
```

**Dispatch:** not authorized by this documentation amendment; no dashboard deployment, code change or PR is included.

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
