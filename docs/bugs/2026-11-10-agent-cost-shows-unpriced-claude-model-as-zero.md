# Bug: Agent Cost dashboard counts an unpriced Claude model (Fable) as $0, silently

**Status:** OPEN
**Priority:** P3
**Waiting on:** dispatch — since 2026-11-10 (P3 batch; WIP 3/3)
**Introduced by:** `1bf0cf40` (v1.43.14, claude-context-cost-per-turn: "0 for an unpriced model"); dashboard side pre-existing
**Should have been caught by:** spec (the exporter counts unpriced messages but no panel shows the count)
**Prior art:** exact-slug glob: none. `make find-similar-docs` not run (vector store unreachable, 2026-11-10)
**Severity:** cosmetic and reporting. Claude API-equivalent cost reads low by whatever Fable (or any new model) used; tokens are still shown by model.
**Approval:** operator, 2026-11-10: "go for those three as you suggested (approved)" (filing)
**Intent approved:** operator, 2026-11-10: "intent approved", in reply to Claude's offer to widen this P3 with the Fable panel and the weekly-limit export (E4-E6 added that turn)
**Widened:** 2026-11-10, folds in the `docs/ideas.md` row "Export the Claude Fable weekly limit" (same dashboard file, one dispatch)
**Filed:** 2026-11-10
**Detected by:** Claude, 2026-11-10, answering the operator's "I wonder if our dashboard can capture Fable's activities" after the operator allowed Fable subagents
**Branch:** `k3d-manager-v1.43.15`

## Evidence (Claude, 2026-11-10)

- `scripts/etc/agent/codex-model-prices.json` `claude_models` has `claude-opus-5-5`, `claude-sonnet-5-5`,
  `claude-haiku-5-5` (checked 2026-10-29); no `claude-fable-5-1`.
- `bin/k3dm-dispatch-metrics:452-456`: `_claude_cost` returns None for a model with no rates; `:502-503` adds it to
  `unpriced` instead of cost; `:529` exports `k3dm_dispatch_claude_unpriced_messages{window}`.
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml`: no panel queries
  `k3dm_dispatch_claude_unpriced_messages` (grep "unpriced": 0 hits), so `k3dm_dispatch_claude_api_cost_usd`
  (`:512`) reads as complete when it is not.
- Tokens are not lost: `:526-528` exports `k3dm_dispatch_claude_tokens{model=...}` for every model, priced or not.

- 2026-11-10 dry run (`bin/k3dm-dispatch-metrics --dry-run`, M4, nothing pushed):
  `k3dm_dispatch_claude_daily_tokens{date="2026-11-10",model="claude-fable-5-1"} 815271` beside Opus 110339660. The
  "Claude tokens per day" panel (`grafana-dashboard-agent-cost.yaml:729`, `sum by (date, model)`) would show
  Fable, but at about 0.3% of the bar height, so you can't see it.
- Fable weekly limit: `${STATUSLINE_CACHE_DIR:-/tmp/claude}/statusline-usage-cache.json` (M4, 2026-11-10 16:30 PST,
  read-only capture) has `limits[]` entries `{kind: session}`, `{kind: weekly_all}` and
  `{kind: weekly_scoped, group: weekly, percent: 1, scope: {model: {id: null, display_name: "Fable"}}, resets_at, is_active}`.
  `_claude_quota` (`bin/k3dm-dispatch-metrics:1976-2000`) reads only the top-level `five_hour` and `seven_day`.

## Fix

1. Add `claude-fable-5-1` rates (input, cache_write_5m, cache_write_1h, cache_read, output) to `claude_models`, and
   bump `checked`. Rates come from Anthropic's published pricing page, captured with URL and date in the PR, not
   from memory (CLAUDE.md "Prove external behaviour").
2. Agent Cost dashboard: a stat beside the Claude cost showing `k3dm_dispatch_claude_unpriced_messages`, red when
   above 0, with a description saying the cost excludes those messages.
3. `_claude_quota`: for each `limits[]` entry with `kind: weekly_scoped` and a `scope.model.display_name`, export
   `k3dm_claude_quota_used_ratio{limit="weekly_<lowercased name>",window_minutes="10080"}` (`percent / 100`) and its
   `k3dm_claude_quota_resets_at_seconds`. Skip malformed entries; keep `five_hour` and `seven_day` unchanged.
4. Agent Cost dashboard: a small "Fable" row with Fable tokens per day on its own axis, and a gauge of the Fable
   weekly limit with its reset time.

## Files

| File | Change |
|---|---|
| `scripts/etc/agent/codex-model-prices.json` | `claude-fable-5-1` rates, `checked` |
| `bin/k3dm-dispatch-metrics` | `_claude_quota`: weekly_scoped limits |
| `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml` | unpriced stat; Fable row |
| `scripts/tests/` (dispatch-metrics and agent-cost dashboard suites) | E1, E2, E4, E5 |

## Contract readers

- `codex-model-prices.json`: reader `bin/k3dm-dispatch-metrics:64` (loads `claude_models`), `:2730` (`--prices`).
  Adding a key changes only Fable's cost from unpriced to priced. Writers: hand edits only.
- `statusline-usage-cache.json` `limits[]`: writer the Claude Code statusline (outside the repo, format captured above);
  new reader `_claude_quota`. A missing or changed entry exports nothing, and nothing errors.
- `k3dm_claude_quota_used_ratio`: writer `bin/k3dm-dispatch-metrics:1998`; readers `git grep` before dispatch (the
  worker lists them). The new `limit` value is additive; existing series are unchanged.
- Agent Cost dashboard: reader Grafana (ArgoCD platform-ops); suite tests that pin its panels must be updated in
  the same change (`scripts/tests/` dashboard suites).

## Acceptance

```yaml
must:
  M1: a Claude record with model claude-fable-5-1 contributes to k3dm_dispatch_claude_api_cost_usd at the published rates
  M2: the Agent Cost dashboard shows the unpriced Claude message count next to the Claude cost
must_not:
  N1: an unpriced model's messages are never shown as covered by the cost figure without the unpriced count beside it
  M3: the Fable weekly limit from the statusline cache is exported as k3dm_claude_quota_used_ratio{limit="weekly_fable"}
  M4: the Agent Cost dashboard shows Fable tokens per day on their own axis and the Fable weekly limit
  N2: Opus, Sonnet and Haiku costs are unchanged for the same input
  N3: the five_hour and seven_day series are unchanged, and a cache without limits[] exports no weekly_fable series and does not error
evidence:
  - {id: E1, proves: [M1, N2], kind: offline, intent: "You will see a test feed one Fable message and one Opus message: Fable's cost matches the captured price page by hand calculation, and Opus's is the same as before the change."}
  - {id: E2, proves: [M2, N1], kind: offline, intent: "You will see a dashboard test find a panel querying k3dm_dispatch_claude_unpriced_messages beside the Claude cost; it fails on today's dashboard."}
  - {id: E4, proves: [M3, N3], kind: offline, intent: "You will see a test feed the captured cache shape (Fable at 1%) and get weekly_fable 0.01 with its reset time and the same five_hour and seven_day lines as before; a cache without limits[] gives no weekly_fable line. Against today's code there is no weekly_fable line."}
  - {id: E5, proves: [M4], kind: offline, intent: "You will see a dashboard test find a Fable row with a per-day Fable tokens panel and a weekly-limit gauge; it fails on today's dashboard."}
  - {id: E6, proves: [M3, M4], kind: live, intent: "After promote, Claude opens Agent Cost and sees the Fable row: the weekly gauge matches the statusline percent, and Fable's daily bars are visible."}
  - {id: E3, proves: [M1, M2], kind: live, intent: "After promote, Claude opens Agent Cost and sees Fable cost above 0 and the unpriced count at 0."}
interface:
  - "bin/k3dm-dispatch-metrics --prices <file> (Prometheus text output)"
  - "scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml"
```

## Worker definition of done

- Change only the price file, `bin/k3dm-dispatch-metrics` (`_claude_quota` only), the Agent Cost dashboard and tests. Show E2's test red on today's dashboard, then
  green. Paste the price-page capture (URL, date) and command, rc and proving lines. Leave changes uncommitted.
