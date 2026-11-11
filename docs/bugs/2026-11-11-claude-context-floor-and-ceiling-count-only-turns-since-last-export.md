# Claude context floor and ceiling count only the turns since the exporter's last run

**Status:** OPEN — found 2026-11-11 by Claude after the operator questioned the panel
**Priority:** P2
**Waiting on:** fix running — since 2026-11-11
**Severity:** medium — Agent Cost "Floor, observed ceiling and configured threshold" reads 99.8K / 99.8K while auto-compaction fires at 163–171K, so the compaction-threshold study (`docs/plans/v1.43.6-claude-context-compaction-metrics.md`) reads wrong data
**Introduced by:** unknown (context turns arrived in 61256041 v1.43.6, the ceiling and floor in 82c1d9c8 v1.43.14; which one dropped persisted turns is not yet traced)
**Should have been caught by:** offline test
**Prior art:** none above threshold (find-similar-docs unavailable: vector store context missing; `ls docs/bugs | grep -E 'ceiling|floor|context'` found no match)
**Approval:** operator, 2026-11-11 ("go ahead to dispatch")
**Intent approved:** operator, 2026-11-11

## Symptom

The operator's screenshot (2026-11-11) shows floor 99.8K, observed 99.8K, configured 200K. The operator sees auto-compaction at about 150–160K+.

## Evidence (Claude, M4, 2026-11-11 04:33–04:38 PST)

- Raw transcripts under `~/.claude/projects/*/*.jsonl`, last 8 `compact_boundary` records with trigger `auto`: preTokens 163598, 168651, 168009, 167249, 170094, 167231, 170867, 167539.
- `bin/k3dm-dispatch-metrics --dry-run` with a **fresh** `--claude-cache` gives ceiling 1d 166986, 7d 180612, 30d 388911, and floor 1d 95330, 7d 84722. These are plausible.
- The same dry run with a **copy of the real cache** (`~/.local/share/k3d-manager/claude-usage/rollup.json`, keys `offsets`, `records`) gives ceiling 121601 and floor 108870 for **every** window (1d = 7d = 30d).
- Cause in the code: `bin/k3dm-dispatch-metrics:268` `if line_pos < offset: continue` runs before the `context_turns.append(...)` at `:278`, and the cache stores only `offsets` and `records`, with no context turns. Each run therefore builds `turns` from lines appended since the previous run. Floor, ceiling, quantiles, `k3dm_claude_context_turns` and the cache-rebuild series all describe that delta, not the window.
- The pushed 99.8K / 99.8K is one such delta: a run where a single post-compaction turn was both the floor and the ceiling.
- Also seen: the M5's `claude-usage/rollup.json` is 27 bytes and its `~/.claude/projects` has no k3d-manager transcripts. Not yet checked: whether the M5 exporter pushes to the same Pushgateway group and blanks or overwrites the M4's Claude series.

## Fix direction

Persist context turns in the cache (or recompute them from all lines within the widest window) so a run with a warm cache emits the same context series as a cold run on the same transcripts. Check the other per-turn series built from `turns` and `boundaries`.

## Files

| File | Change |
|---|---|
| `bin/k3dm-dispatch-metrics` | context turns (and compaction boundaries they pair with) survive a warm cache: persisted in the cache, or recomputed over the widest window |
| `scripts/tests/bin/test_dispatch_metrics.py` | E1, E2 |

## Worker definition of done

- Change only the files above. Keep the cache backward compatible: an old cache without the new key must still work (treat it as cold for context turns).
- Read-only real-data run: `bin/k3dm-dispatch-metrics --dry-run` with a copy of `~/.local/share/k3d-manager/claude-usage/rollup.json` in a scratch dir and `K3DM_PUSHGATEWAY_URL=http://127.0.0.1:9`; warm and cold runs must give the same `k3dm_claude_context_*` lines. Never push metrics.
- Show every `must_not` test red against today's code, then green. Mutation-test each guard (break it, see the test fail, restore). Run the full touched suites, not only the new tests, and run the change once read-only against real data where the spec says how. Paste command, rc and the proving lines for each; list every error you saw, and any choice the spec left open. Leave changes uncommitted; Claude reviews and lands.

## Acceptance

```yaml
must:
  - id: M1
    text: with a warm cache, context floor, ceiling, quantiles and turn counts equal those of a cold-cache run on the same transcripts
  - id: M2
    text: windows differ when the transcripts differ across windows (1d ceiling ≤ 7d ceiling ≤ 30d ceiling)
must_not:
  - id: N1
    text: a second run with no new transcript lines changes or drops any k3dm_claude_context_* series
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    intent: "a test runs the exporter twice on fixed transcripts (cold, then warm with no new lines) and gets identical context series; it fails on today's code"
  - id: E2
    proves: [M2]
    kind: offline
    intent: "a test with turns at 2h, 3d and 20d ago gets three different ceilings for 1d, 7d and 30d"
  - id: E3
    proves: [M1]
    kind: live
    intent: "after promote, Agent Cost shows an observed ceiling near the 160-170K where auto-compaction fires, and a floor below it"
interface:
  - bin/k3dm-dispatch-metrics --dry-run --claude-projects DIR --claude-cache FILE --claude-usage-cache FILE
```

## Contract readers

`~/.local/share/k3d-manager/claude-usage/rollup.json`: writer and reader `bin/k3dm-dispatch-metrics` (`--claude-cache`, default at `:2768`). Others to grep in the spec. Series readers: `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml` (floor/ceiling panel, mean context per turn, cache rebuilds).
