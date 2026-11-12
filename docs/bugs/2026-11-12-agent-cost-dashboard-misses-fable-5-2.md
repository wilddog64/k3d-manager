# Agent Cost dashboard and price table know only claude-fable-5-1; Fable 5.2 runs are uncounted

**Status:** OPEN — captured 2026-11-12
**Priority:** P2
**Classified:** P2 by gemini-4-argon-medium, 2026-11-12 (cost observability degraded; the gauge and raw metrics remain); Claude proposed P3. Higher stands until the operator decides.
**Triage:** carry → v1.44.0 (cost-dashboard batch) — grooming 2026-11-12, operator.
**Waiting on:** dispatch — since 2026-11-12
**Introduced by:** pre-existing (Fable 5.2 became the subagent default after the panel was written)
**Should have been caught by:** none
**Prior art:** not run
**Approval:** none yet (capture only)

The "Fable tokens per day" panel queries only `k3dm_dispatch_claude_daily_tokens{model="claude-fable-5-1"}`
(`scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml:1542`), and
`scripts/etc/agent/codex-model-prices.json:37-41` prices only `claude-fable-5-1`. Fable subagents now run
`claude-fable-5-2`: the 2026-11-12 review transcript shows 80 messages with `"model":"claude-fable-5-2"` and
none with 5.1. Its tokens therefore don't show on the panel and aren't priced. The weekly-limit gauge
reads the statusline cache and is unaffected.

Fable 5.2 API rates (claude-api skill, cached 2026-11-03): $8 input, $40 output, $0.20 cache read per MTok.
Cache-write rates for 5.2 need a capture from the pricing page before they go into the table (5.1 read
2026-11-10: $12.50 5m, $20 1h).
