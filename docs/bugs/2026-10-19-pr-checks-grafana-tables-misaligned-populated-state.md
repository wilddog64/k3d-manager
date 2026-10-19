# Bug: PR Checks Grafana tables misalign query fields and leak empty-state placeholders when PRs exist

**Filed:** 2026-10-19 (operator screenshot)
**Status:** OPEN — investigation and fix pending
**Priority:** P3 — dashboard presentation/data interpretation defect; GitHub scraping appears healthy
**Severity:** low (potentially misleading CI/PR status)
**Approval:** bug filing requested by operator, 2026-10-19; implementation not yet authorized
**Release:** v1.43.5 (triage; confirm target release before implementation)
**Component:** `scripts/etc/argocd/platform-ops/grafana-dashboard-pr-checks.yaml` (table panels 5 and 6)
**Related:** `docs/bugs/2026-10-18-pr-checks-dashboard-empty-tables-read-as-no-data.md` (previous no-PR empty-state improvement), `docs/plans/v1.43.3-pr-checks-dashboard.md`

## Symptom / evidence

Operator screenshot on 2026-10-19, dashboard **k3dm PR Checks**, repo filter **All**, last 24 hours:

- Summary shows **Open PRs = 1**, **Failing = 0**, **Running = 0**, **Last scrape = 1.40 mins**, **GitHub read = ok**. Collector appears active; do not treat this as a confirmed scrape failure.
- **Open PRs** table includes actual shopping-cart **PR #62**, head `8aef1cf3`, but also a second `No open PRs` row despite a PR being open. Columns **Value #A** and **Value #B** leak raw query values; **Overall** contains unexpected `No open PRs` / `success` values across rows instead of one clean PR record.
- **Checks per PR** table has **PR = 1.03 mins** (a duration displayed where the PR number belongs); the **Duration** column contains `No open PRs — no checks to show` rather than a numeric duration. **Value #A** and extra placeholder-like values appear, while check names and statuses are otherwise present.
- Screenshot contains real check rows, including GitGuardian, lint, integration, and security checks; therefore the no-PR/no-check placeholders are incorrect in the populated state.

## Investigation notes (not yet root-cause confirmed)

Current dashboard config on `k3d-manager-v1.43.5` uses two instant Prometheus table targets per panel followed by a Grafana `merge` and `organize` transformation. Both queries carry numeric `Value` fields that Grafana may name `Value #A` and `Value #B`. The `organize` exclusion removes `Value` but does not explicitly exclude or correctly map all resulting suffixed fields. The previous fix set `fieldConfig.defaults.noValue` on each table, which may turn missing fields in otherwise populated rows into misleading `No open PRs` text.

Investigate actual Grafana frame schemas, transformation/join keys, duplicate rows, time-series label/value handling, field overrides and duration unit formatting. Confirm independently rather than assuming one particular Grafana behavior. Do not modify the Hermes collector unless evidence shows source metrics are invalid.

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
