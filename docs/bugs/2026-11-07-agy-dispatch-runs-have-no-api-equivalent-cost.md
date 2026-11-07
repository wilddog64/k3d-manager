# Bug: agy dispatch runs show no API equivalent cost

**Status:** OPEN — fix specced and dispatched 2026-11-07
**Priority:** P3
**Waiting on:** fix running — since 2026-11-07
**Severity:** low — the Agent Cost Per spec table leaves API eq. blank for every agy (Gemini) task, so Gemini work looks unpriced next to Codex work
**Approval:** operator, 2026-11-07 ("go ahead to file a small P3 for agy and dispatch to Luna")
**Assigned:** Luna (`MODEL=gpt-6-luna`)
**Filed:** 2026-11-07
**Detected by:** the operator, on the Agent Cost dashboard Per spec table ("why thes two has no API eq")
**Affected:** `bin/k3dm-dispatch-metrics` (`_cost`, `:692`), `scripts/etc/agent/codex-model-prices.json`
**Branch:** `k3d-manager-v1.43.15`

## Observed failure

The Per spec table showed two v1.43.15 agy rows, with 2.06 M and 494 K tokens. Both had an empty API eq. cell; Codex
rows beside them were priced.

## Root cause

Two gaps, and both have to be closed:

1. **No Gemini rates.** `scripts/etc/agent/codex-model-prices.json` `models` lists only `gpt-5.6-luna`, `gpt-6-luna`,
   `gpt-6.1-terra` and `gpt-6.1-sol`. `_cost` returns `None` for any other model, and the guide
   (`docs/guides/grafana-dashboards/k3dm-agent-cost.md:106`) defines an empty cell as "at least one session is
   unpriced".
2. **agy usage has another shape.** `_cost` reads a flat `codex_usage` event (`model`, `input`, `cached_input`,
   `output`). agy runs record usage nested under `usage`, with no `model` field. The model is on the run's `start`
   event. Captured from `~/.local/share/k3d-manager/worktrees/ledger.jsonl` on the M4, 2026-11-07 (abridged):

   ```
   {"ts":1794085895,"event":"start","version":"v1.43.15","slug":"2026-11-02-hub-data-export-never-ran","run":1,"agent":"agy","model":"gemini-3.8-flash-medium",...}
   {"ts":1794087195,"event":"agent_exit","version":"v1.43.15","slug":"2026-11-02-hub-data-export-never-ran","exit":0,"usage":{"input_tokens":951876,"output_tokens":54141,"thinking_tokens":23889,"cache_read_tokens":51703491,"total_tokens":1006017},"run":1,...}
   {"ts":1794087195,"event":"agent_usage","version":"v1.43.15","slug":"2026-11-02-hub-data-export-never-ran","usage":{"input_tokens":951876,"output_tokens":54141,"thinking_tokens":23889,"cache_read_tokens":51703491,"total_tokens":1006017},"run":1}
   ```

   From these numbers, `total_tokens` = `input_tokens` + `output_tokens`. So `input_tokens` excludes cache reads
   (cache reads are 54× larger), and `output_tokens` excludes thinking. The same run's usage appears on both
   `agent_exit` and `agent_usage`.

## Rates (captured)

Google AI Studio pricing, `https://aistudio.google.com/docs/pricing` (redirected from
`ai.google.dev/gemini-api/docs/pricing`), Standard tab, Paid Tier, USD per 1 M tokens, read by Claude 2026-11-07.
Output prices are labelled "Output price (including thinking tokens)". There is no prompt-size tier.

| Model id | Input | Cached input | Output | Changes on |
|---|---|---|---|---|
| `gemini-3.8-flash` | 0.75 | 0.075 | 3.75 | 2027-01-01 → 1.50 / 0.15 / 7.50 |
| `gemini-4-argon` | 2.00 | 0.10 | 10.00 | 2026-12-01 → 4.00 / 0.20 / 20.00 |

## Fix

1. Add `gemini-3.8-flash` and `gemini-4-argon` to `models` in `codex-model-prices.json`, with the current rates from
   the table, as `input`, `cached_input` and `output`. Extend `source` with the URL, the read date and both change
   dates. Leave `checked` as it is unless you also re-verify the OpenAI rates (you do not).
2. In `bin/k3dm-dispatch-metrics`, price agy runs:
   - one usage record per `(version, slug, run)`; the same run on `agent_exit` and `agent_usage` counts once;
   - model = the `model` of that run's `start` event, with a trailing `-low`, `-medium` or `-high` thinking-level
     suffix removed, so `gemini-3.8-flash-medium` is priced as `gemini-3.8-flash`;
   - cost = (`input_tokens` × input + `cache_read_tokens` × cached_input + (`output_tokens` + `thinking_tokens`) ×
     output) / 1 000 000;
   - a run whose model has no price entry, or whose usage is missing or malformed, stays unpriced exactly as an
     unpriced Codex session does today.

   Feed these into the same API eq., Codex-at-API-prices and Per landed totals that Codex sessions feed. Reuse the
   per-run usage source the Tokens column already uses for agy rows, so tokens and cost always describe the same
   records. Name it in your final message.
3. Update `docs/guides/grafana-dashboards/k3dm-agent-cost.md`: API equiv. covers priced Codex **and agy** sessions; give
   the agy formula, the suffix rule, and that the Gemini rates change on the dates above.

## Files

- `scripts/etc/agent/codex-model-prices.json`
- `bin/k3dm-dispatch-metrics`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `docs/guides/grafana-dashboards/k3dm-agent-cost.md`

## What NOT to do

- Do not use any rate not in the table above, and do not add a model the table does not list.
- Do not change how Codex sessions are priced, or any OpenAI or Claude rate.
- Do not rename `codex-model-prices.json` or change its `--prices` default.
- Do not add effective-date logic for the scheduled price changes; that is a separate decision.
- Do not edit dashboard JSON.
- Do not run git add, commit or push, and do not touch `memory-bank/`.

## Acceptance

```yaml
must:
  M1: an agy run with model gemini-3.8-flash-medium and the captured usage above is priced with the gemini-3.8-flash rates and the formula in the Fix, input excluding cache reads and thinking billed as output
  M2: the agy run's cost is included in the API eq. of its landed task and in the Codex-at-API-prices and Per landed totals
  M3: codex_usage pricing produces the same output as before for the same ledger
  M4: the guide documents agy pricing, the suffix rule and the scheduled rate changes
must_not:
  N1: a run whose usage appears on both agent_exit and agent_usage is never counted twice
  N2: an agy run whose model has no price entry (for example gemini-9-unknown-medium) never gets a cost and keeps its task's API eq. empty (paired control for M1)
  N3: thinking_tokens are never dropped from the cost
evidence:
  E1:
    proves: [M1, M2, M3, N1, N2, N3]
    kind: offline
    intent: >-
      You will see test_dispatch_metrics.py feed a fixture ledger with the captured start, agent_exit and agent_usage
      lines for one agy run, one Codex session, and one agy run on an unpriced model. It asserts the agy cost equals
      the hand-computed value, the Codex cost is unchanged, the unpriced run stays unpriced, and the duplicate run is
      counted once. The M1 and N1 assertions are red on the pre-fix exporter.
    what: python3 -m pytest scripts/tests/bin/test_dispatch_metrics.py
  E2:
    proves: [M2]
    kind: live
    intent: >-
      After make platform-ops, Claude or the operator sees a dollar value in API eq. for the v1.43.15 agy rows of the
      Agent Cost Per spec table.
    what: Agent Cost dashboard, Per spec table
interface:
  - bin/k3dm-dispatch-metrics (Prometheus text output, --prices)
  - scripts/etc/agent/codex-model-prices.json
```
