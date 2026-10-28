# Bug: Bug Tracking Target state blocker reason is too small to read and does not wrap

**Filed:** 2026-10-27, operator screenshot and explicit P3 filing request
**Status:** VERIFIED — operator normal-width rendering passed; narrow-width live check pending
**Fix commit:** 2f551fc7090dea8416f7a008eb9881048a7d66ea
**Priority:** P3
**Severity:** low — readability/accessibility defect; target-state calculation remains correct
**Release:** v1.43.9 (bug; does not count toward the five-plan cap)
**Branch:** `k3d-manager-v1.43.9`
**Approval:** explicit operator 2026-10-28 Luna implementation batch; live deployment remains operator-run
**Dispatch:** go — gpt-6-luna, target-state-readable-reason-luna
**Component:** `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` — Bug Tracking / Release forecast, Target state (panel 31)
**Related:** `docs/plans/v1.43.5-release-forecast.md`; `docs/bugs/2026-10-25-release-forecast-ignores-live-window-and-unnamed-blocker.md`
**Found by:** operator, screenshot 2026-10-27 approximately 11:00 PDT

## Symptom and evidence

The Bug Tracking dashboard's **Target state** panel shows the large orange `blocked` status correctly, but the explanatory line is rendered in extremely small text (operator could not read it at normal dashboard zoom). The explanatory message refers to the external v1.49.0 blocker, `TwinkleAI app M1 near done (app repo)`. The panel has space available but does not wrap the longer sentence into legible lines.

The existing October 25 bug fixed the **meaning** of the blocker (identify v1.49.0 and its cause), and was live-verified. This is a **new presentation/readability regression or remaining defect**, not grounds to reopen the prior calculation bug. The exact Grafana panel config and its available text modes require inspection before selecting an implementation; do not assume changing a `fontSize` field unsupported by the deployed panel solves it.

## Expected behavior

- Preserve the status and its semantic mapping (blocked / after_blocked and existing status colors).
- Display the complete blocking reason at **at least 14 px, ideally 16 px** at typical operator browser zoom, with multi-line wrapping where needed. Do not truncate or rely on hover-only text.
- Keep the large primary `blocked` indication prominent; put reason in a clearly readable supporting text region with left alignment where possible.
- Responsive at ordinary full-width and narrowed panel sizes; no clipping or overlapping title, status, explanatory text.
- When not blocked, do not display a stale blocking reason.
- Preserve forecast, milestone and blocker data-source/query semantics.

## Investigation and fix scope

1. Inspect panel 31's Grafana type, transformations, field mappings, text sizing and current `blocked_by` reason source; verify whether the existing stat can render wrapped secondary text at a controllable size. If not, use a supported, minimal sibling text/table panel or separate row and retain the main stat. Do not replace an accessible semantic label with a tiny annotation.
2. Fix presentation only in `grafana-dashboard-bugs.yaml`; leave `bin/k3dm-vectordb-metrics`, release-milestones inventory, source status and forecast logic untouched unless a specific proven data issue requires a separate defect.
3. Update applicable Bug Tracking dashboard guide and add an offline dashboard-configuration regression test. Validate JSON/YAML and panel IDs/queries and test both blocked and non-blocked mapping.
4. Capture operator-approved live Grafana screenshots at normal zoom, both full-width and narrow panel, showing the full blocker sentence legibly. Mark live-verified only after that evidence.

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`
- `scripts/tests/plugins/grafana_dashboard_bugs.bats`
- `docs/guides/grafana-dashboards.md`
- `CHANGELOG.md` if a production-facing fix is landed

## Acceptance

```yaml
must:
  - id: M1
    text: Target state retains the correct main status and identifies the external blocker (v1.49.0 / TwinkleAI app M1).
  - id: M2
    text: Entire explanation is readable at normal zoom with >=14px equivalent text and wraps at narrow widths, without needing a hover tooltip.
  - id: M3
    text: Blocked and non-blocked states do not show stale or contradictory explanations.
  - id: M4
    text: Layout, queries, threshold colors and panel ID remain valid and other Release forecast panels do not regress.
must_not:
  - id: N1
    text: No truncation, single-line miniature reason text, overflow or overlapping labels.
  - id: N2
    text: No status or forecast calculation change to solve a presentation-only problem.
evidence:
  - id: E1
    kind: offline
    text: Dashboard config tests check source/query continuity and readable reason implementation; reject old tiny single-line presentation.
  - id: E2
    kind: live
    text: Operator screenshots at normal browser zoom in full and narrowed Grafana layout show complete readable blocked reason and correct main status.
```

## Definition of Done

- [x] Operator approved implementation in the 2026-10-28 Luna batch.
- [x] Independent 38/38 dashboard BATS; only panel31 text sizes changed, exact query/mappings/layout preserved.
- [ ] Visual/operator acceptance demonstrates wrapped, readable blocker reason at normal zoom.
- [ ] Record fix commit, live evidence, verified timestamp and update status after actual validation.

## What NOT to Do

- Do not change TwinkleAI milestone dependency or claim that v1.49.0 is unblocked.
- Do not use browser zoom or a tooltip as the only readability solution.
- Do not deploy, merge, create a PR or commit to `main` while filing this bug.

## Authorized Luna batch — 2026-10-28 (current instructions)

Operator explicitly requested dispatch of this screenshot bug to GPT-6-Luna,
independent coordinator verification, then operator live checks one at a time.
This authorizes the bounded implementation/review below and supersedes older
filing-only/not-authorized wording. No deployment, live provider requests,
service restarts, Keychain reads/writes, credential changes, screenshot exports,
PRs or main-branch changes are authorized to the worker. Work in the isolated
worktree only. Do not edit memory-bank, this spec or source plan statuses.
Do not stage/commit/push. Preserve DO NOT REMOVE comments. Coordinator owns
staged gates, commit/push/landing and records. New/refactored functions <=8ifs;
never weaken audit or hooks. Report unexpected failures verbatim.

Use existing panel31 stat, fixed supported title/value sizing and a readable
wrapping layout; no new sibling panel/table/row, no unrelated layout/width or
Plans changes. Current Grafana11.4.0 upstream BigValueLayout supports
options.text.titleSize/valueSize; title div has ordinary wrapping CSS and
flex container flexWrap wrap. Inspect before choosing sizing; do not invent
unsupported options. Preserve main status, colors, exact query and blocked
reason displayName. Aim title16px/value40px, fit normal/narrow panel without
truncation; live width acceptance remains operator-owned. If existing stat
cannot meet acceptance, report that limit and propose a bounded alternative
instead of silently adding UI. Avoid stale reason in nonblocked fixtures.
Primary source: https://github.com/grafana/grafana/blob/v11.4.0/packages/grafana-ui/src/components/BigValue/BigValueLayout.tsx
Rules gates: bats scripts/tests/plugins/grafana_dashboard_bugs.bats; parse
YAML/JSON, confirm only panel31 changed and query/mappings unchanged; diffcheck.
Use existing regression suite, meaningful pre-fix red, no broad refactoring.

## Independent offline verification — 2026-10-28

GPT-6-Luna task target-state-readable-reason-luna landed as2f551fc7.
Existing stat sets supported options.text.titleSize16/valueSize40; no new
panel or query/status/layout change. Independent38BATS, YAML/JSON structural
comparison, staged lint/audit, hooks and dispatcher post-rebase tests pass.
Config tests reject old missing sizing. Actual full output and live checklist:
[batch evidence](../issues/2026-10-28-three-bug-luna-batch-verification.md).
Full and narrow rendering/wrapping remain operator acceptance, not assumed.

## Operator normal-width live rendering — PASS (2026-10-28)

Screenshot shows full supporting reason across three visible lines:
`blocked at v1.49.0:` / `TwinkleAI app M1 near` / `done (app repo)`.
Reason is visibly larger than the original tiny annotation, wraps without
truncation, and does not overlap the prominent orange `blocked` status.
Other forecast tiles remain present (18 releases, median0.510, no-date labels).
This verifies supplied normal-width rendering only; narrow layout remains E2
acceptance before LIVE-VERIFIED. No screenshot export or runtime mutation.
[Textual evidence](../issues/2026-10-28-three-bug-luna-batch-verification.md).
