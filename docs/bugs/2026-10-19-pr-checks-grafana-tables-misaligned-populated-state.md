# Bug: PR Checks Grafana tables misalign query fields and leak empty-state placeholders when PRs exist

**Filed:** 2026-10-19 (operator screenshot)
**Status:** OPEN — investigation and fix pending
**Priority:** P3 — dashboard presentation/data interpretation defect; GitHub scraping appears healthy
**Severity:** low (potentially misleading CI/PR status)
**Approval:** bug filing requested by operator, 2026-10-19; implementation not yet authorized
**Release:** v1.43.5 (triage; confirm target release before implementation)
**Component:** `scripts/etc/argocd/platform-ops/grafana-dashboard-pr-checks.yaml` (table panels 5 and 6)
**Related:** `docs/bugs/2026-10-18-pr-checks-dashboard-empty-tables-read-as-no-data.md` (previous no-PR empty-state improvement), `docs/bugs/2026-10-19-pr-checks-check-duration-legend-clipped.md` (panel 8 legend layout), `docs/plans/v1.43.3-pr-checks-dashboard.md`

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-pr-checks.yaml`
- `scripts/tests/plugins/grafana_dashboard_pr_checks.bats`

## Symptom / evidence

Operator screenshot on 2026-10-19, dashboard **k3dm PR Checks**, repo filter **All**, last 24 hours:

- Summary shows **Open PRs = 1**, **Failing = 0**, **Running = 0**, **Last scrape = 1.40 mins**, **GitHub read = ok**. Collector appears active; do not treat this as a confirmed scrape failure.
- **Open PRs** table includes actual shopping-cart **PR #62**, head `8aef1cf3`, but also a second `No open PRs` row despite a PR being open. Columns **Value #A** and **Value #B** leak raw query values; **Overall** contains unexpected `No open PRs` / `success` values across rows instead of one clean PR record.
- **Checks per PR** table has **PR = 1.03 mins** (a duration displayed where the PR number belongs); the **Duration** column contains `No open PRs — no checks to show` rather than a numeric duration. **Value #A** and extra placeholder-like values appear, while check names and statuses are otherwise present.
- Screenshot contains real check rows, including GitGuardian, lint, integration, and security checks; therefore the no-PR/no-check placeholders are incorrect in the populated state.

## Investigation notes (not yet root-cause confirmed — superseded by "Root cause and fix direction — 2026-10-20" below)

Current dashboard config on `k3d-manager-v1.43.5` uses two instant Prometheus table targets per panel followed by a Grafana `merge` and `organize` transformation. Both queries carry numeric `Value` fields that Grafana may name `Value #A` and `Value #B`. The `organize` exclusion removes `Value` but does not explicitly exclude or correctly map all resulting suffixed fields. The previous fix set `fieldConfig.defaults.noValue` on each table, which may turn missing fields in otherwise populated rows into misleading `No open PRs` text.

Investigate actual Grafana frame schemas, transformation/join keys, duplicate rows, time-series label/value handling, field overrides and duration unit formatting. Confirm independently rather than assuming one particular Grafana behavior. Do not modify the Hermes collector unless evidence shows source metrics are invalid.

## Root cause and fix direction — 2026-10-20 (Antigravity agent; evidence-based)

Root cause is now confirmed by simulation; the investigation notes above predate it. Method: the hub Grafana (11.4.0, `kube-prometheus-stack-grafana`, default datasource uid `prometheus`) was queried through `/api/ds/query` with the dashboard's exact targets, and the returned frames were run through Grafana 11.4.0's own `@grafana/data` code (`joinByField`, `organize`) with a copy of `@grafana/prometheus` `transformDFToTable`. Live data: one open PR (`wilddog64/shopping-cart-product-catalog` #62) with 7 checks. The simulation harness is not in the repo.

| Variant | Panel 5 (Open PRs) | Panel 6 (Checks per PR) |
|---|---|---|
| Original (`merge` + `organize`) | 2 rows; `Value #A` / `Value #B` leak; `Overall` null on the info row and `Draft/Head/Title` null on the overall row | 14 rows; `Value #A` leaks; `Duration` null on every state row and `State` null on every duration row |
| `label_join` + `joinByField` (outer, key `__join`) with `organize` — the first Codex attempt (task `pr-checks-table-misalignment-r4`) | 1 row but columns `Draft, Head, pr 1, repo 1, Title, pr 2, repo 2, Overall` | 7 rows but columns `check 1, pr 1, repo 1, State, check 2, pr 2, repo 2, Duration` |
| Same, with the **second** query aggregated (below) | 1 row: `Draft, Head, PR, Repo, Title, Overall` | 7 rows: `Check, PR, Repo, State, Duration` |

**Why the original misaligns:** `merge` concatenates the two queries' frames instead of joining them, so each metric's value stays in its own `Value #A` / `Value #B` column on its own row.

**Why the first join attempt is still wrong:** both queries return the same label set (`repo`, `pr`, and for panel 6 `check`). `joinByField` keeps both copies and renames them `repo 1` / `repo 2` (and `pr`, `check`), so `organize.renameByName` for `repo`, `pr` and `check` never matches and the table shows duplicate columns.

**Fix (verified in simulation, not yet in the dashboard YAML):**

1. Keep the `label_join` on every target that creates `__join` (Prometheus and Grafana both preserve a label named `__join`; confirmed against the live API).
2. Aggregate the **second** query so it keeps only the join key (plus the one label it must contribute), which removes the duplicate labels:
   - Panel 5, query B: `max by (__join, state) (label_join(k3dm_pr_overall{repo=~"$repo"},"__join",":","repo","pr"))`
   - Panel 6, query B: `max by (__join) (label_join(k3dm_pr_check_duration_seconds{repo=~"$repo"},"__join",":","repo","pr","check"))`
   - Query A of each panel stays as `label_join(...)` without aggregation (panel 5 A = `k3dm_pr_info`, panel 6 A = `k3dm_pr_check_state`), so it supplies `repo`, `pr`, `check`, `title`, `head`, `draft`, `state`.
3. Keep `transformations` as `joinByField` (`{"byField":"__join","mode":"outer"}`) followed by `organize`. In `organize.excludeByName` hide `Time`, `Value`, `Value #A`, `__name__`, `__join`, `job`, `instance`; additionally hide `Value #B` for panel 5 only. Panel 6 must **keep** `Value #B` so `renameByName` can turn it into `Duration`.
4. Keep `fieldConfig.defaults.noValue` and all existing mappings, units and `sortBy` unchanged; the empty state must still read "No open PRs" / "No open PRs — no checks to show".

**Simulation results with the fix (live data):** repo `.*` gives panel 5 = 1 row and panel 6 = 7 rows with exactly the columns above and `Duration` populated (2, 32, 5, 0, 51, 27, 24 s); a single-repo filter gives the same; a non-matching repo returns no rows, so `noValue` still applies. The pre-fix queries reproduce the operator screenshot's symptoms (leaked `Value #A/#B`, `Duration` null).

**Regression test requirement (existing test is insufficient):** the first Codex attempt added a BATS test that joins plain Python dictionaries; it passes against the broken duplicate-label variant, so it cannot detect this defect. The test must assert on the dashboard JSON that (a) query B of panels 5 and 6 aggregates with `max by (__join` and does not carry `repo`, `pr` or `check` outside the join key, (b) query A is not aggregated, (c) `joinByField` precedes `organize`, (d) panel 5 hides `Value #B` and panel 6 does not, and (e) `Value #B` is renamed to `Duration` in panel 6. Keep the existing empty-state test intact.

**Not verified:** real browser rendering of the panels (simulation ran Grafana's transformation code in Node, not the UI); `repo=All` with several repos at once (live data has one repo and one PR); mixed states beyond `success` and `skipped`. These belong to the live check (E2).

## Expected behavior

1. When one or more PRs exist, **Open PRs** shows one row per `(repo, pr)`, with correct `Draft`, `Head`, `PR`, `Repo`, `Title`, and `Overall` fields; no placeholder rows, raw value columns, or mismatched status.
2. **Checks per PR** shows one row per `(repo, pr, check)`; `PR` is the actual PR number, `State` is the check state, and `Duration` is a numeric duration with appropriate unit. No empty-state phrase appears inside a populated table.
3. When zero PRs are open, both tables retain an accurate empty-state indication without inventing data rows; retain the prior 2026-10-18 improvement.
4. Repo=All and an individual repo filter both display correct data, including mixed states (success, failure, running, skipped) where available.
5. Do not change collector metrics, stat-panel queries, CI jobs, or unrelated Grafana dashboards solely to address a table transformation issue.

## Reproduction

1. Ensure `k3dm PR Checks` has at least one open PR with check data (the screenshot shows shopping-cart PR #62).
2. Open the dashboard with `repo=All` and a 24-hour window.
3. Inspect **Open PRs** (panel 5) and **Checks per PR** (panel 6) for misplaced `Value #A/#B` columns, wrong PR/duration mapping, and `No open PRs` embedded in populated rows.
4. Repeat with an individual repo selected.
5. Verify the 0-open-PR path after any fix.

## Acceptance

```yaml
must:
  - id: M1
    text: Populated Open PRs panel has one correctly joined row per repo/pr with valid named fields and no synthetic empty-state record.
  - id: M2
    text: Populated Checks per PR panel has one correctly joined row per repo/pr/check; PR is an ID, State is a check state, and Duration is numeric/time-formatted.
  - id: M3
    text: Empty state remains unambiguously informative when there are genuinely zero open PRs, preserving the prior no-PR improvement.
  - id: M4
    text: Filtering by All and by one repo yields correct rows without accidental cross-repo joins.
must_not:
  - id: N1
    text: Raw Value #A / Value #B columns or a misleading No open PRs placeholder appear within populated table rows.
  - id: N2
    text: A duration is shown under PR or an empty-state message is shown under Duration.
  - id: N3
    text: Existing stats, collector health, or underlying PR/check facts are altered solely to hide display errors.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, N1, N2, N3]
    text: Automated dashboard JSON and transformation regression checks covering zero, one, and multiple PRs across repos; show a negative pre-fix case and validate manifests.
  - id: E2
    kind: live
    proves: [M1, M2, M3, M4, N1, N2]
    text: Capture Grafana panel screenshots and/or inspect transformed data frames after the exact fix commit is synced, first with PR and check data, then with zero PRs; record environment, commit SHA, timestamp, and evidence.
interface:
  - scripts/etc/argocd/platform-ops/grafana-dashboard-pr-checks.yaml (panels 5/6)
```

## Definition of Done

- [ ] Root cause identified using actual Grafana frames/transformations; raw collector data compared with rendered table.
- [ ] Offline regressions pass for populated, mixed-repo and empty states.
- [ ] Live verification proves correct populated rows and correct empty-state handling against the deployed commit.
- [ ] Bug status and live evidence are updated only after the corresponding checks succeed.
