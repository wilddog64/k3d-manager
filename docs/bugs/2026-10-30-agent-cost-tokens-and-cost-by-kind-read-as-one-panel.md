# Bug: Agent Cost tokens-by-kind and cost-by-kind panels read as the same panel

**Status:** OPEN
**Priority:** P3
**Approval:** operator, 2026-10-30 ("go ahead to file P3 bug", after proposing the merged table)
**Filed:** 2026-10-30
**Detected by:** operator (reading Agent Cost on the hub)
**Affected:** `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml` panels 86 and 88
**Branch:** `k3d-manager-v1.43.12`
**Related:** `docs/bugs/2026-10-25-claude-tokens-per-day-no-cache-kind-breakdown.md` (added panel 88)

## Observed failure

Panels 86 **Claude tokens by kind** (token count, `h8 w6 x12 y27`) and 88 **Claude cost by kind**
(USD, `h8 w6 x18 y27`) sit side by side as identical horizontal bargauges with the same four rows.
Their titles differ by one word, so the operator read them as two copies of one panel whose numbers
disagree (2.0 B cache_read tokens next to $406.85 cache_read cost). Nothing on either panel connects
a token count to its cost.

## Root cause

Panel 88 was built as a copy of panel 86's layout (F2 of the related bug), with only the metric and
unit changed. Two panels of the same shape invite comparison of numbers that measure different things.

## Fix

Replace panels 86 and 88 with one table panel, id 86, titled **Claude tokens and cost by kind**, at
`h8 w12 x12 y27`. Remove panel 88.

- Query A: `sum by (kind) (k3dm_dispatch_claude_tokens{window="$window"})`, instant, table format.
- Query B: `sum by (kind) (k3dm_dispatch_claude_api_cost_by_kind_usd{window="$window"})`, instant, table format.
- Transformations: `merge` on `kind`, then `calculateField` (binary: cost ÷ tokens × 1,000,000) named
  `$ per million tokens`, then `organize` to columns **Kind**, **Tokens** (unit `short`), **Cost (USD)**
  (unit `currencyUSD`, 2 decimals), **$ per million tokens** (unit `currencyUSD`, 2 decimals), and hide
  `Time`.
- Sort by **Cost (USD)** descending.
- Description: tokens and API-equivalent cost per kind for the selected window or release; cache reads
  are most of the volume but cost a fraction of the input rate, which the last column shows.

No producer change: both series already exist.

Update `scripts/tests/plugins/agent_dispatch_dashboard.bats` (the two tests asserting panels 86 and 88)
and the panel bullets in `docs/guides/grafana-dashboards/k3dm-agent-cost.md` to the merged panel.
Takes effect after `make platform-ops`.

## Acceptance

```yaml
must:
  M1: Agent Cost has one panel titled "Claude tokens and cost by kind", type table, reading both k3dm_dispatch_claude_tokens and k3dm_dispatch_claude_api_cost_by_kind_usd for window="$window" as instant queries.
  M2: The panel shows a per-kind $ per million tokens column computed from cost and tokens.
  M3: The panel occupies h8 w12 x12 y27, and panel 87 keeps h8 w24 x0 y35.
  M4: The Agent Cost guide describes the merged panel and no longer names the two separate panels.
must_not:
  N1: No panel titled "Claude tokens by kind" or "Claude cost by kind" remains, and no panel has id 88.
  N2: No two Agent Cost panels overlap in gridPos.
evidence:
  E1: {proves: [M1, M2, M3, N1, N2], kind: offline, what: "bats scripts/tests/plugins/agent_dispatch_dashboard.bats; the M1 and N1 tests red on the pre-fix dashboard"}
  E2: {proves: [M1, M2], kind: live, what: "after make platform-ops, the hub Agent Cost shows the merged table with four kind rows; operator or Claude reads it"}
interface:
  - scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml (agent-cost.json panels)
  - docs/guides/grafana-dashboards/k3dm-agent-cost.md
```
