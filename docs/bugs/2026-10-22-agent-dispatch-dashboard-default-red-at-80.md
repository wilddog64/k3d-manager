# Bug: agent-dispatch dashboard panels turn red at 80 with no meaning

**Filed:** 2026-10-22 (Claude, from the operator's screenshots of Land outcomes and the stat column)
**Status:** LIVE-VERIFIED 2026-10-24 (E2) — operator screenshot of Agent Dispatch (7d): Accepted specs 94 and Codex tokens / spec 90.4K in neutral blue; Land outcomes landed bar 93 green. Was FIXED offline — `b6c09614` (Luna; Claude review: queries/titles/layout unchanged, N1 red on pre-fix, bats green); live E2 pending ArgoCD sync + a dashboard screenshot
**Priority:** P3 — cosmetic; the numbers are right, the colour implies a problem that does not exist
**Severity:** low
**Approval:** approved — operator, 2026-10-22: "go ahead" to file and queue for Luna after ask-docs-reply-truncation
**Fix commit:** `b6c09614`
**Live evidence:** 2026-10-24 · run operator-screenshot-agent-dispatch-top-row · env hub · scenario neutral-counts-green-landed-above-80 · commit 521c3a24 · proves E2
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Component:** `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`

## Symptom

On the Codex dispatch dashboard, the "landed" bar in Land outcomes (86) shades from green to red,
and Accepted specs (86) and Codex tokens per accepted spec (107K) show in red. The operator asked
why they turned red; nothing is wrong.

## Root cause

Nine stat/bargauge panels set no `fieldConfig.defaults.thresholds` or `color`, so Grafana applies
its default: green, then red at 80. Any count or measure above 80 turns red. The bar gauge's
default gradient fades the bar toward red as it nears 80.

Panels with no colour rule (id, title): 1 Accepted specs, 3 Claude lines changed per task,
4 Wait minutes per task, 5 Codex tokens per accepted spec, 6 Running, 7 Awaiting land,
8 Land outcomes, 10 Minutes to land per spec, 11 Codex minutes per spec. Panels 2 Landing success,
9 Time since last dispatch update and 13 Rework rate already set meaningful thresholds; leave them
unchanged.

## Fix

- **F1.** Panels 1, 3, 4, 5, 6, 7, 10, 11: set `fieldConfig.defaults.color` to
  `{"mode": "fixed", "fixedColor": "blue"}` and `thresholds` to a single base step
  `{"mode": "absolute", "steps": [{"color": "blue", "value": null}]}`. They are measurements with
  no good/bad cut-off, so they get one neutral colour.
- **F2.** Panel 8 Land outcomes: set `options.displayMode` to `"basic"` (no gradient), a neutral
  fixed default colour, and `fieldConfig.overrides` by series name: `landed` → fixed green;
  `rebase`, `scope`, `tests` → fixed orange. Keep the query and legend unchanged.
- **F3.** Test in `scripts/tests/plugins/agent_dispatch_dashboard.bats`: every stat/bargauge panel
  has an explicit `thresholds` or a `color.mode` of `fixed`; Land outcomes overrides map `landed` to
  green and each refusal reason to a non-green colour; panels 2, 9 and 13 keep their existing
  thresholds unchanged.
- **F4.** `CHANGELOG.md` entry.

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: Every stat and bargauge panel on the agent-dispatch dashboard has an explicit colour rule (thresholds or fixed colour mode).
  - id: M2
    text: In Land outcomes, the landed series is green and the rebase, scope and tests series are a non-green warning colour, at any value.
  - id: M3
    text: Landing success, Time since last dispatch update and Rework rate keep their existing thresholds exactly.
must_not:
  - id: N1
    text: No stat or bargauge panel may rely on Grafana's default thresholds (red at 80) (red on the pre-fix code).
  - id: N2
    text: No panel query (targets expr) or legend may change.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, N1, N2]
    text: bats scripts/tests/plugins/agent_dispatch_dashboard.bats; N1 red on the pre-fix code.
  - id: E2
    kind: live
    proves: [M1, M2]
    text: After the dashboard syncs, the operator's screenshot shows Accepted specs and Codex tokens in a neutral colour and the landed bar green while above 80.
interface:
  - ConfigMap data JSON in scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml (panels[].fieldConfig, panels[].options, panels[].targets)
```

## Definition of Done

- [ ] F1–F4 on `k3d-manager-v1.43.5`; only the Files above change.
- [ ] N1 shown red against the pre-fix code.
- [ ] Commit: `fix(dashboards): give agent-dispatch panels explicit colours instead of default red at 80`

## What NOT to Do

- Do NOT change any query, panel id, title, layout or the three panels that already have thresholds.
- Do NOT edit this bug doc, create a PR, commit to `main`, or use `--no-verify`.
