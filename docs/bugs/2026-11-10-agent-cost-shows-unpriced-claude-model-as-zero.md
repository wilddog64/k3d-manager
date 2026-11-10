# Bug: Agent Cost dashboard counts an unpriced Claude model (Fable) as $0, silently

**Status:** OPEN
**Priority:** P3
**Waiting on:** operator decision — since 2026-11-10 (intent approval)
**Introduced by:** `1bf0cf40` (v1.43.14, claude-context-cost-per-turn: "0 for an unpriced model"); dashboard side pre-existing
**Should have been caught by:** spec (the exporter counts unpriced messages but no panel shows the count)
**Prior art:** exact-slug glob: none. `make find-similar-docs` not run (vector store unreachable, 2026-11-10)
**Severity:** cosmetic and reporting. Claude API-equivalent cost reads low by whatever Fable (or any new model) used; tokens are still shown by model.
**Approval:** operator, 2026-11-10: "go for those three as you suggested (approved)" (filing)
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

## Fix

1. Add `claude-fable-5-1` rates (input, cache_write_5m, cache_write_1h, cache_read, output) to `claude_models`, and
   bump `checked`. Rates come from Anthropic's published pricing page, captured with URL and date in the PR, not
   from memory (CLAUDE.md "Prove external behaviour").
2. Agent Cost dashboard: a stat beside the Claude cost showing `k3dm_dispatch_claude_unpriced_messages`, red when
   above 0, with a description saying the cost excludes those messages.

## Contract readers

- `codex-model-prices.json`: reader `bin/k3dm-dispatch-metrics:64` (loads `claude_models`), `:2730` (`--prices`).
  Adding a key changes only Fable's cost from unpriced to priced. Writers: hand edits only.
- Agent Cost dashboard: reader Grafana (ArgoCD platform-ops); suite tests that pin its panels must be updated in
  the same change (`scripts/tests/` dashboard suites).

## Acceptance

```yaml
must:
  M1: a Claude record with model claude-fable-5-1 contributes to k3dm_dispatch_claude_api_cost_usd at the published rates
  M2: the Agent Cost dashboard shows the unpriced Claude message count next to the Claude cost
must_not:
  N1: an unpriced model's messages are never shown as covered by the cost figure without the unpriced count beside it
  N2: Opus, Sonnet and Haiku costs are unchanged for the same input
evidence:
  - {id: E1, proves: [M1, N2], kind: offline, intent: "You will see a test feed one Fable message and one Opus message: Fable's cost matches the captured price page by hand calculation, and Opus's is the same as before the change."}
  - {id: E2, proves: [M2, N1], kind: offline, intent: "You will see a dashboard test find a panel querying k3dm_dispatch_claude_unpriced_messages beside the Claude cost; it fails on today's dashboard."}
  - {id: E3, proves: [M1, M2], kind: live, intent: "After promote, Claude opens Agent Cost and sees Fable cost above 0 and the unpriced count at 0."}
interface:
  - "bin/k3dm-dispatch-metrics --prices <file> (Prometheus text output)"
  - "scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml"
```

## Worker definition of done

- Change only the price file, the Agent Cost dashboard and tests. Show E2's test red on today's dashboard, then
  green. Paste the price-page capture (URL, date) and command, rc and proving lines. Leave changes uncommitted.
