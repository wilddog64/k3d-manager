# Bug: Bug Tracking dashboard tests check panel structure, never whether a query matches the metrics

**Filed:** 2026-10-23 (Claude, found during live E3 of `release-plan-tracking`)
**Status:** FIXED offline — `baa2d055` (Luna, two rework fixes by Claude); E1, E3 and the E2 local skip verified 2026-10-24; E2's "not skipped in CI" check waits for the v1.43.5 PR run
**Priority:** P2 — a wrong query ships green and shows "No data" or duplicate rows; the only check is a person looking at the live dashboard
**Severity:** medium
**Approval:** approved to file — operator, 2026-10-23: "file a bug (maybe P2) for what you discovered"
**Dispatch go:** operator, 2026-10-24: "let's get those two dispatched" (after Claude proposed no open P0–P2 at release cut).
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Component:** `scripts/tests/plugins/grafana_dashboard_bugs.bats`, `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`
**Related:** `docs/plans/v1.43.5-release-plan-tracking.md`, `docs/bugs/2026-10-18-dispatch-dashboard-window-variable-confused-with-time-picker.md`
**Fix commit:** `baa2d055`
**Offline evidence (2026-10-24, Claude):** real promtool via Docker `prom/prometheus:v3.1.0`, 1 passed. Red on two mutated dashboard copies: `release_order=~"$release"` (queries 18 and 26 return nothing) and a bare `or` instead of `or on(plan)` (the undispatched-plan row disappears). With no promtool or Docker on PATH, the test reports SKIP with its reason. Claude's fixes on top of Luna's rework: the fixture now passes a real `fixed_in`, and the table-column check ignores Grafana's `Time`/`Value #X` fields.

## Symptom

Plan `release-plan-tracking` landed at `10362f51` with every offline gate green: 102 pytest, 93 BATS,
5/5 mutations caught. Three query defects in the new Release plans row passed every gate:

| Defect | Effect | Found by | Fix |
|---|---|---|---|
| Plans table fallback used a bare `or` | every dispatched plan listed twice, once as "no record" | Claude's review, by reading the query | `ee28dbb5` → `10362f51`: `or on(plan)` |
| Panels filtered `release_order=~"$release"` | the whole row showed 0 and "No data" on the live hub | the operator's screenshot, after deploy | `44ff27ba`: `release=~"$release"` |
| "no record" mapped from an empty `dispatch_state` | with no plan dispatched, the label was absent, so the Dispatch columns did not exist | the operator's screenshot, after the fix above | fallback sets `dispatch_state="none"` via `label_replace`; `none` maps to "no record" |

Both errors were in the spec Claude wrote, and Luna implemented them as written. The dashboard tests
could not catch them, because they assert on the dashboard JSON text, for example that `' or '`
appears in the expr. They never check whether a query selects the series the producer emits.

## Root cause

- The `release` variable is `label_values(k3dm_bug_info{repo="$repo"}, release_order)` with the regex
  `/^\S+ (?<value>\S+)$/`, so its value is `v1.43.5`. The label `release_order` holds
  `9998.9956.9994 v1.43.5`, and `=~` is anchored, so `release_order=~"$release"` never matches. The
  existing bug panels filter on `release`. Nothing records that convention, and no test checks it.
- PromQL `a or b` keeps the series from `b` whose full label set has no match in `a`. After
  `group_left(dispatch_state, slug)`, the left side carries two more labels, so every right-side
  series is kept as well. Only evaluating the query shows this.
- The producer and the dashboard are tested separately. The producer tests check exposition lines;
  the dashboard tests check JSON. No test joins the two.

The same pattern shows up in the producer: `_plan_texts` read from a git ref returned 0 files,
because every test passed `texts=` directly and none read from a ref. That one was fixed in review
(`10362f51`, `test_plan_metrics_reads_git_ref_top_level_only`).

## Fix

- **F1. Query check against producer-shaped series.** Add a test that, for every panel in
  `grafana-dashboard-bugs.yaml`:
  1. takes sample series from the real producers run offline: `_plan_metrics`, `_bug_metrics` and
     `_bug_status_metrics` in `bin/k3dm-vectordb-metrics` on a fixture tree, and `render` in
     `bin/k3dm-dispatch-metrics` on a fixture ledger;
  2. substitutes the dashboard variables the way Grafana does, applying each variable's `regex` to
     its `label_values` result;
  3. evaluates every target expr against those series and asserts that it returns at least one
     series. A `table` target must return one row per entity, and every column its `organize`
     transformation names must exist; for the Plans table, one row per plan with a `dispatch_state`.

  Evaluate with real PromQL: `promtool test rules`, using each expr as a recording rule, from a pinned
  `prom/prometheus` image (or a local `promtool` when present). Skip only when neither is available,
  and say so loudly; never pass silently.
- **F2. Record the convention.** In `docs/guides/grafana-dashboards.md`, state that panels filter on
  `release=~"$release"` and that `release_order` is used only for sorting. Spec templates for new
  dashboard panels must cite it.
- **F3.** `CHANGELOG.md` entry.

## Files

- `scripts/tests/plugins/grafana_dashboard_bugs.bats` or a new `scripts/tests/bin/test_dashboard_queries.py`
- `scripts/tests/fixtures/` (new fixture series or ledger, if needed)
- `docs/guides/grafana-dashboards.md`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: Every target expr in grafana-dashboard-bugs.yaml is evaluated with real PromQL against series produced offline by the real producers, with the dashboard variables substituted the way Grafana does (including each variable's regex).
  - id: M2
    text: A panel expr that returns no series for the fixture's current release fails the test.
  - id: M3
    text: The Plans table returns exactly one row per plan in the fixture, dispatched or not.
  - id: M4
    text: docs/guides/grafana-dashboards.md states the release-versus-release_order filter convention.
must_not:
  - id: N1
    text: A panel filtering release_order=~"$release" must not pass (red on 10362f51's dashboard).
  - id: N2
    text: A Plans table using a bare `or` must not pass (red with `or on(plan)` reverted to `or`).
  - id: N3
    text: The test must not pass silently when no PromQL evaluator is available; it skips with a visible reason, and CI must have an evaluator.
  - id: N4
    text: No test reaches the live Prometheus, Pushgateway or Grafana.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, N1, N2, N4]
    text: The new test passes on the current dashboard, fails on 10362f51's dashboard (release_order matcher), and fails with `or on(plan)` changed to `or`.
  - id: E2
    kind: offline
    proves: [N3]
    text: With promtool and docker removed from PATH, the test reports a skip with the reason; in CI it runs, and the job log shows it was not skipped.
  - id: E3
    kind: offline
    proves: [M4]
    text: The guide section exists and the new test cites it in its failure message.
interface:
  - scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml (dashboard JSON, templating.list)
  - bin/k3dm-vectordb-metrics (_plan_metrics, _bug_metrics, _bug_status_metrics)
  - bin/k3dm-dispatch-metrics render
  - promtool test rules
```

## Definition of Done

- [ ] F1–F3 on `k3d-manager-v1.43.5`; only the Files above change.
- [ ] N1 and N2 shown red.
- [ ] Commit: `test(dashboards): evaluate Bug Tracking queries against producer-shaped series`

## What NOT to Do

- Do NOT query the live Prometheus, Pushgateway or Grafana from a test.
- Do NOT change any panel query in this fix; the two known defects are already fixed.
- Do NOT create a PR, commit to `main`, or use `--no-verify`.

**CI evidence (E2):** CI run 40124898903 on `eae158cc` (2026-10-24, PR #148): `scripts/tests/bin/test_dashboard_queries.py .` — ran against a real promtool 3.1.0 and passed, not skipped.
