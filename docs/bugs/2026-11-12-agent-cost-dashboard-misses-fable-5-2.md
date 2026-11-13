# Agent Cost dashboard and price table know only claude-fable-5-1; Fable 5.2 runs are uncounted

**Status:** LANDED — `bac099be` on k3d-manager-v1.44.0 2026-11-13 (Codex Luna; Claude verified: E1–E4 red on pre-fix, green on fix, 50/50 bats, 205 pytest; Fable review no high/medium; Claude added the reset-gauge single-step thresholds override from Fable's low, mutant red); originally captured 2026-11-12
**Priority:** P2
**Classified:** P2 by gemini-4-argon-medium, 2026-11-12 (cost observability degraded; the gauge and raw metrics remain); Claude proposed P3. Higher stands until the operator decides.
**Triage:** carry → v1.44.0 (cost-dashboard batch) — grooming 2026-11-12, operator.
**Waiting on:** live check — since 2026-11-13 (E5, after a hub promote: Fable panel shows 11-11..11-13 bars, reset gauge not red)
**Introduced by:** pre-existing (Fable 5.2 became the subagent default after the panel was written)
**Should have been caught by:** none
**Prior art:** `docs/bugs/2026-11-10-dispatch-table-shows-flash-and-fable-as-other.md` (exact-topic read) — same allowlist pattern, fixed for 5-1 only; `make find-similar-docs` not run
**Approval:** operator, 2026-11-13: "approved"
**Dispatch go:** operator, 2026-11-13: "approved"
**Intent approved:** operator, 2026-11-13
**Intent approval words:** "approved", in reply to Claude's E1–E5 intents

The "Fable tokens per day" panel queries only `k3dm_dispatch_claude_daily_tokens{model="claude-fable-5-1"}`
(`scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml:1542`), and
`scripts/etc/agent/codex-model-prices.json:37-41` prices only `claude-fable-5-1`. Fable subagents now run
`claude-fable-5-2`: the 2026-11-12 review transcript shows 80 messages with `"model":"claude-fable-5-2"` and
none with 5.1. Its tokens therefore don't show on the panel and aren't priced. The weekly-limit gauge
reads the statusline cache and is unaffected.

Fable 5.2 API rates (claude-api skill, cached 2026-11-03): $8 input, $40 output, $0.20 cache read per MTok.
Cache-write rates for 5.2 need a capture from the pricing page before they go into the table (5.1 read
2026-11-10: $12.50 5m, $20 1h).

## Live capture (2026-11-13, hub Prometheus 127.0.0.1:19091 via ssh m5-air.local, read-only)

`sum by (model,date) (k3dm_dispatch_claude_daily_tokens{model=~".*fable.*"})`:

| date | model | tokens |
|---|---|---|
| 2026-11-10 | claude-fable-5-1 | 815,271 |
| 2026-11-11 | claude-fable-5-2 | 9,294,155 |
| 2026-11-12 | claude-fable-5-2 | 30,368,938 |
| 2026-11-13 | claude-fable-5-2 | 746,089 |

The producer already labels by the transcript's model id; only the panel filter, the price table and the
identity allowlist (`bin/k3dm-dispatch-metrics:41`) are pinned to 5-1. The panel shows 2.2% of the real Fable volume.

Second defect on the same panel group (operator screenshot 2026-11-13): the "resets at" gauge override
(`grafana-dashboard-agent-cost.yaml` ~1620) sets only `unit: dateTimeFromNow`, so it inherits `min 0`, `max 1` and the
0.7/0.9 thresholds; a millisecond timestamp is always above 0.9, so the arc is always full red, even 6 days out.

Cache-write rates are now captured: claude-api skill `shared/models.md` (bundled 2.1.322, read 2026-11-13):
Fable 5.2 $8 input / $40 output, cache read $0.20, 5-minute cache write $10, 1-hour $16 per MTok.

## Fix

- Panel: `sum by (date) (k3dm_dispatch_claude_daily_tokens{model=~"claude-fable-.*"})`, description "all Fable versions".
- `scripts/etc/agent/codex-model-prices.json`: add `claude-fable-5-2` (8.00 / 10.00 / 16.00 / 0.20 / 40.00); keep 5-1; `claude_checked` 2026-11-13.
- `bin/k3dm-dispatch-metrics` `MODEL_IDENTITY_ALLOWLIST`: add `claude-fable-5-2`.
- "resets at" override: add `min`/`max` that keep the arc meaningful (or `color: fixed` with no threshold colouring) so it is not red unless the reset is near; simplest acceptable: fixed neutral colour.

## Acceptance

```yaml
must:
  M1: the Fable tokens-per-day panel query matches every claude-fable-* model id, summed per date
  M2: claude-fable-5-2 messages are priced at 8.00/10.00/16.00/0.20/40.00 per MTok, and 5-1 prices are unchanged
  M3: a dispatch run whose worker identity is claude-fable-5-2 displays "anthropic/claude-fable-5-2 (...)", not "other"
  M4: the "resets at" gauge field no longer inherits the 0..1 used-ratio thresholds (fixed colour or its own range)
must_not:
  N1: the panel query still names only claude-fable-5-1
  N2: any other model's price, the used-ratio gauge thresholds (0.7/0.9) or any other panel changes
evidence:
  - {id: E1, proves: [M1, N1], kind: offline, intent: "You will see the dashboard test require a query that matches all Fable versions; it fails on today's dashboard, which names only 5-1."}
  - {id: E2, proves: [M2, N2], kind: offline, intent: "You will see a metrics test where a Fable 5.2 message is costed at the 5.2 rates and a 5.1 message at the old ones; on today's price file the 5.2 message costs nothing."}
  - {id: E3, proves: [M3], kind: offline, intent: "You will see a dispatch run on Fable 5.2 shown by its model name; today it shows 'other'."}
  - {id: E4, proves: [M4, N2], kind: offline, intent: "You will see the dashboard test check that the reset-time field has its own colour, while the percent-used gauge keeps its yellow and red marks."}
  - {id: E5, proves: [M1, M4], kind: live, intent: "After the dashboard is promoted, you will see bars for 11-11, 11-12 and 11-13 on the Fable panel and a non-red reset gauge."}
interface:
  - "grafana-dashboard-agent-cost.yaml Fable row panels"
  - "bin/k3dm-dispatch-metrics --prices scripts/etc/agent/codex-model-prices.json"
```

## Contract readers

- `scripts/etc/agent/codex-model-prices.json` — readers: `bin/k3dm-dispatch-metrics:2776` (`--prices` default), `scripts/tests/bin/test_dispatch_metrics.py:3649`; writers: none (hand-maintained). Additive key; readers unchanged.
- `MODEL_IDENTITY_ALLOWLIST` — reader `bin/k3dm-dispatch-metrics:1689`; additive.

## Files

| File | Change |
|---|---|
| `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml` | Fable daily query + description; resets-at override |
| `scripts/etc/agent/codex-model-prices.json` | add claude-fable-5-2, claude_checked |
| `bin/k3dm-dispatch-metrics` | allowlist |
| `scripts/tests/plugins/agent_dispatch_dashboard.bats` | E1, E4 (replace the 5-1 assertion at ~1287) |
| `scripts/tests/bin/test_dispatch_metrics.py` | E2, E3 |

## Worker definition of done

- Change only the files above. No network, no hub, no Pushgateway (`PUSHGATEWAY_URL=http://127.0.0.1:9`), scratch HOME. Show E1–E4 red on today's code, then green. Run `bats scripts/tests/plugins/agent_dispatch_dashboard.bats` and `PYTHONPATH=scripts/lib python3 -m pytest scripts/tests/bin/test_dispatch_metrics.py -q`; paste command, rc and proving lines. Leave changes uncommitted.



## Residual lows (from Fable review, 2026-11-13)

- Test 49 checks the override's JSON, not Grafana's rendering; E5 is the real proof.
- `agent_dispatch_dashboard.bats:1288` asserts the prose "all Fable versions"; a description reword breaks it.
- The 5.2 cost test checks one summed total; two offsetting rate errors would pass.
