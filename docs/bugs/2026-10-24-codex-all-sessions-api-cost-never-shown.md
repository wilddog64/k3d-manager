# Bug: "Codex at API prices, all sessions" never shows a value

**Status:** LIVE-VERIFIED — `b14dab86` (Luna, dispatched by the operator; landed 2026-10-24 by Claude). E1 offline-verified: dashboard BATS 16/16, pytest 81 passed, validate-manifests 83 valid; the new pytest fails on the pre-fix exporter (N1). Real-data dry run at 7d: exec $5.09, interactive $7.04, 70 unpriced sessions. E2 live-verified 2026-10-24 (PDT): operator screenshot of Agent Activity at Window 7d shows Codex at API prices, all sessions $12.1 and Unpriced Codex sessions 70, matching the dry run.
**Live evidence:** 2026-10-24 · run operator-screenshot-209 · env hub/k3d-k3d-cluster · scenario agent-activity-codex-api-cost · commit b14dab86 · proves E2
**Fix commit:** b14dab86
**Priority:** P3
**Severity:** low — one stat panel on the Agent Activity dashboard is always No data; the dispatcher-only cost panels are unaffected
**Release:** bug (does not count toward the five-plan cap); candidate for the vendor-LLM P2/P3 trial
**Filed:** 2026-10-24, by Claude, while live-checking `docs/plans/v1.43.6-dispatch-codex-solo-activity.md` E3
**Approval:** explicit 2026-10-24, as part of the bug cleanup the operator approved ("sounds like a plan"). Not critical (laptop exporter and a dashboard panel), so it may dispatch once written.
**Component:** `bin/k3dm-dispatch-metrics` (`_activity_metrics`), `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml` (panel 58; moved there by the v1.43.6 dashboard split, `4cb877c7`)
**Related:** `docs/plans/v1.43.6-dispatch-codex-solo-activity.md` (lines 99–100 set the omit rule)

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`
- `docs/guides/grafana-dashboards.md`

## Problem

Plan 3 says `k3dm_codex_api_cost_usd{window,mode}` is omitted for a mode when any of its sessions is
unpriced. On real data that is nearly every mode, so the panel never shows a number. Tally of the
session files the exporter reads, 2026-10-24 (all windows, by mode and reason):

| mode | priced | model `codex-auto-review` | model `gpt-5.6-terra` | no usage |
|---|---|---|---|---|
| exec | 380 | 100 | 0 | 4 |
| interactive | 5 | 62 | 1 | 14 |

`codex-auto-review` is Codex's built-in review model. It has no public API price, so adding it to
`scripts/etc/agent/codex-model-prices.json` would mean inventing a rate. Sessions that ended before
writing a token count have no usage. Both are permanent, so the all-or-nothing rule hides the
priced 385 sessions forever.

## Fix

1. Export the priced sum per mode whenever at least one session in it is priced, and add
   `k3dm_codex_unpriced_sessions{window,mode,reason}` with `reason` `model` or `usage`.
2. Panel 58 on Agent Activity shows the priced sum. Place the new unpriced-count stat on the same dashboard, inside the All Codex activity row, with no overlap and no gap. Update the guide's Agent Activity section to say the total covers priced sessions only. Its description says it covers priced sessions only, and a second
   stat (or an override line) shows the unpriced session count beside it, the same way
   **Ledger coverage** shows spend outside the ledger.
3. Do not add a price for `codex-auto-review` or any model without a published rate.

## Tests

pytest in `scripts/tests/bin/test_dispatch_metrics.py`, with fixture sessions only:

1. One priced and one `codex-auto-review` session in the same mode: the cost line equals the priced
   session's cost, and `k3dm_codex_unpriced_sessions{...,reason="model"}` is 1.
2. A session with no usage counts under `reason="usage"`.
3. A mode with only unpriced sessions emits no cost line, and the unpriced count is still exported.
4. The dashboard panels stay non-overlapping.

## Acceptance

```yaml
must:
  - id: M1
    text: k3dm_codex_api_cost_usd is exported for a mode with at least one priced session, as the sum of its priced sessions.
  - id: M2
    text: k3dm_codex_unpriced_sessions{window,mode,reason} counts sessions left out, with reason model or usage.
  - id: M3
    text: The dashboard shows the priced total and the unpriced count, and says the total covers priced sessions only.
must_not:
  - id: N1
    text: One unpriced session must not hide a mode's cost (red on the pre-fix exporter, which omits the line).
  - id: N2
    text: No price may be invented for a model without a published rate.
  - id: N3
    text: No test may read the real ~/.codex or push to the hub Pushgateway (use K3DM_DISPATCH_PUSHGATEWAY_URL=http://127.0.0.1:9).
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, N1, N2, N3]
    text: pytest and the dashboard BATS green; N1 red on the pre-fix exporter in a temp copy.
  - id: E2
    kind: live
    proves: [M1, M3]
    text: After the next metrics push, the operator's screenshot at Window 7d shows a dollar value in Codex at API prices, all sessions, with the unpriced count beside it.
interface:
  - bin/k3dm-dispatch-metrics --dry-run --codex-home PATH --prices PATH
  - Agent Activity dashboard (/d/k3dm-agent-activity), row "All Codex activity"
```

## What NOT to Do

- Do NOT read session contents beyond the fields the exporter already reads (model, usage, mode, repo).
- Do NOT change the dispatcher-only cost panels.
- Do NOT edit `scripts/lib/foundation/`.
