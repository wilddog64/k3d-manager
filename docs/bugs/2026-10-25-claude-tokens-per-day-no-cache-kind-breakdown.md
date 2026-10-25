# Bug: Agent Cost cannot show Claude tokens per day or cost by cache kind

**Status:** FIXED 2026-10-25 — `79fab0b1`; pytest 119/119, BATS 23/23, validate-manifests 85/85; Luna showed the new tests red on pre-fix copies. Live E2 pending the operator's screenshot.
**Fix commit:** `79fab0b1`
**Review note:** Claude raised the dashboard `$window` expression count 58 → 60. Claude's panel 86 (`ccf7d21e`) had already broken it at 59 because pytest was not rerun before that commit. Luna's `_claude_cost` now treats non-numeric or negative usage as unpriced (N3). Offline on real data, the cost kinds sum to the total in every scope and each day's kinds equal its per-model total. At 7d: cache_read $125.00, cache_write $90.47, output $57.11, input $0.04 of $272.63.
**Priority:** P3
**Severity:** low — the per-day bars read as cost, but about 98% of them are cheap cache reads
**Release:** v1.43.7 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-25, by Claude, from the operator's question "are we able to create a cache breakdown?" (screenshot 278)
**Approval:** explicit 2026-10-25 ("go ahead for what you suggested option 1 now and file option 2 as P3 and dispatch to Luna"). Not critical (metrics script and one dashboard ConfigMap).
**Component:** `bin/k3dm-dispatch-metrics` (`_render_claude`, daily Claude tokens), `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml`
**Related:** panel 86 **Claude tokens by kind** (`ccf7d21e`), which splits a whole window by kind

## Problem

Agent Cost panel 32 (**Claude tokens per day**) stacks each day's Claude tokens by model, from
`k3dm_dispatch_claude_daily_tokens{date,model}`. That series has no kind, so a day cannot be split
into cache reads, cache writes, uncached input and output. Over 7d on 2026-10-25, Opus 5.5 was 622.5M
cache read, 11.2M cache write, 2.8M output and 10K input. A 255M bar is therefore mostly tokens billed
at a tenth of the input rate, and nothing on the dashboard says which kinds the dollars come from.

## Fix

### F1. Daily tokens by kind

Next to the existing `k3dm_dispatch_claude_daily_tokens` loop, emit
`k3dm_dispatch_claude_daily_tokens_by_kind{date="<YYYY-MM-DD>",kind="<kind>"}`, using the same records,
the same local-date rule, the same 30-day cut-off and the same `<synthetic>` exclusion. Kinds:
`input` (`input`), `cache_write` (`cache_5m` + `cache_1h`), `cache_read` (`cache_read`), `output`
(`output`). Skip a zero value. For each date, the sum over kinds equals the sum over models of
`k3dm_dispatch_claude_daily_tokens`.

### F2. Claude cost by kind

In `_render_claude`, for every scope that emits `k3dm_dispatch_claude_api_cost_usd`, also emit
`k3dm_dispatch_claude_api_cost_by_kind_usd{window="<window>",kind="<kind>"}` with the same four kinds:
each priced record's kind tokens times its rate (`cache_write` uses `cache_write_5m` for `cache_5m` and
`cache_write_1h` for `cache_1h`), divided by 1,000,000, times the same `share` used for the total.
Unpriced records are left out, as they are from the total. Per scope, the four values sum to
`k3dm_dispatch_claude_api_cost_usd` within 1e-6. Emit all four kinds, zeros included, whenever the
total is emitted.

Do not change `k3dm_dispatch_claude_daily_tokens`, `k3dm_dispatch_claude_tokens` or any existing value.

### F3. Two panels on Agent Cost

- Panel **87**, **Claude tokens per day by kind**: a barchart like panel 32 (same x-axis, stacking,
  value labels and unit), query `sum by (date, kind) (k3dm_dispatch_claude_daily_tokens_by_kind)`,
  legend `{{kind}}`, gridPos `{"h": 8, "w": 24, "x": 0, "y": 35}`.
- Panel **88**, **Claude cost by kind**: a horizontal bargauge like panel 86 (instant query, name left,
  fixed text sizes), unit `currencyUSD`, decimals 2, query
  `k3dm_dispatch_claude_api_cost_by_kind_usd{window="$window"}`, legend `{{kind}}`, gridPos
  `{"h": 8, "w": 8, "x": 16, "y": 27}`.
- Each has a description saying what the kinds are and that cache reads are billed at a fraction of
  the input rate. Panel 32 is unchanged.

### F4. Docs

`docs/guides/grafana-dashboards.md`, Agent Cost list: one bullet per new panel, beside the existing
**Claude tokens by kind** bullet.

## Tests

In `scripts/tests/bin/test_dispatch_metrics.py`:

1. Records on two local dates with all five usage fields → `k3dm_dispatch_claude_daily_tokens_by_kind`
   has the right value per date and kind; `cache_write` is `cache_5m + cache_1h`.
2. For each date, the sum over kinds equals the sum over models of `k3dm_dispatch_claude_daily_tokens`.
3. `<synthetic>` records and records older than 30 days are excluded, as for the existing series.
4. `k3dm_dispatch_claude_api_cost_by_kind_usd` values for a known record and known rates, including a
   record using both cache write durations.
5. For a release scope and a time window, the four kinds sum to `k3dm_dispatch_claude_api_cost_usd`
   within 1e-6, and an unpriced record changes neither.
6. Existing Claude series are byte-identical to the pre-fix output for the same fixture.

In `scripts/tests/plugins/agent_dispatch_dashboard.bats`:

7. Panels 87 and 88 exist with the queries, units, layout and legend above; panel 32 is unchanged. Update
   the panel-id set assertions to include 87 and 88 (the only change allowed to existing assertions).

Tests 1, 4 and 7 must be red on a temp copy of the pre-fix files.

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`
- `docs/guides/grafana-dashboards.md`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: k3dm_dispatch_claude_daily_tokens_by_kind{date,kind} gives each local day's Claude tokens split into input, cache_write, cache_read and output, and per day its kinds sum to the existing per-model daily total.
  - id: M2
    text: k3dm_dispatch_claude_api_cost_by_kind_usd{window,kind} gives Claude API-equivalent cost per kind for every scope that has a Claude cost, and the kinds sum to k3dm_dispatch_claude_api_cost_usd.
  - id: M3
    text: Agent Cost shows Claude tokens per day by kind (panel 87) and Claude cost by kind (panel 88).
  - id: M4
    text: The guide describes both panels.
must_not:
  - id: N1
    text: No change to any existing series name, label set or value.
  - id: N2
    text: Panel 32 and every other existing panel unchanged.
  - id: N3
    text: A record with missing or non-numeric usage fields must not stop the metrics run or emit an invalid exposition line.
  - id: N4
    text: Tests never push to the real Pushgateway.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, N1, N2, N3, N4]
    text: K3DM_DISPATCH_PUSHGATEWAY_URL=http://127.0.0.1:9 pytest scripts/tests/bin/test_dispatch_metrics.py and bats scripts/tests/plugins/agent_dispatch_dashboard.bats green; tests 1, 4 and 7 red on a temp copy of the pre-fix files; make validate-manifests passes.
  - id: E2
    kind: live
    proves: [M1, M2, M3]
    text: After the next metrics push and dashboard sync, the operator's screenshot of Agent Cost at Window 7d shows per-day bars stacked by kind with cache_read the largest, and a cost-by-kind gauge whose values sum to Claude at API prices.
interface:
  - bin/k3dm-dispatch-metrics --dry-run (env K3DM_DISPATCH_PUSHGATEWAY_URL, Claude projects dir as the existing tests set it)
  - k3dm_dispatch_claude_daily_tokens_by_kind{date,kind}
  - k3dm_dispatch_claude_api_cost_by_kind_usd{window,kind}
  - Grafana /d/k3dm-agent-cost panels 87 and 88
```

## Definition of Done

- [ ] F1–F4 and a CHANGELOG `[Unreleased]` `### Added` entry; only the Files above change.
- [ ] E1 green; paste the summaries.
- [ ] Tests 1, 4 and 7 shown red on a temp copy of the pre-fix files.
- [ ] Commit: `feat(dispatch): Claude tokens per day and cost by cache kind`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT change existing series, panel 32, or any other existing panel.
- Do NOT push to the real Pushgateway; tests use `K3DM_DISPATCH_PUSHGATEWAY_URL=http://127.0.0.1:9`.
- Do NOT change or remove existing tests or assertions, except the panel-id sets in test 7.
- Do NOT modify files outside the Files list.
