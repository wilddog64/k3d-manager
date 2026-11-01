# Bug: the "Auto-compact threshold" panel shows the configured value, which never took effect

**Status:** OPEN
**Priority:** P3
**Severity:** low — the panel showed 400K from 2026-10-22 to 2026-11-01 while every auto-compaction ran at about 168K, so the context-window trial looked active when it measured nothing; no runtime impact
**Approval:** operator, 2026-11-01 ("please dispatch this one to Luna too")
**Filed:** 2026-11-01
**Detected by:** operator (dashboard 400K vs the statusline's ctx …/200k), root cause by Claude
**Affected:** `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml` (panel "Auto-compact threshold")
**Branch:** `k3d-manager-v1.43.13`
**Related:** `docs/metrics/context-window-experiment.md` (2026-11-01 correction row); `docs/plans/v1.43.6-claude-context-compaction-metrics.md`

## Observed failure

On 2026-11-01 the agent-activity dashboard showed "Auto-compact threshold 400 K" while the Claude Code statusline showed
`ctx 133k/200k`. The 400K value is the `autoCompactWindow` setting written on 2026-10-22. It never applied: the session
context window is 200K and the setting cannot exceed it. Transcript `compact_boundary` records show 140
auto-compactions from 2026-10-22 to 2026-11-01 at 166K–213K (median ~168K), the same as the 72 before (166K–180K).

After the experiment log got its 200000 correction row, the hub Prometheus returned
`k3dm_claude_auto_compact_tokens{job="k3dm-dispatch"} 200000` (push 2026-11-01T13:18:11Z, read-only query on the M5),
so the panel now reads 200K. It is still the configured value, and it would show any future setting the same way,
whether or not it applies.

## Root cause

The panel queries `k3dm_claude_auto_compact_tokens`. `bin/k3dm-dispatch-metrics` takes that from the latest
non-future row of the settings table in `docs/metrics/context-window-experiment.md`, which is what was configured,
not what happened. The exporter already publishes what happened:
`k3dm_claude_compactions{window,trigger}` and `k3dm_claude_compaction_pre_tokens_sum{window,trigger}` (from
`compactMetadata.preTokens` in the transcripts), but no panel shows the context size at compaction.

## Fix

Dashboard only. Do not change `bin/k3dm-dispatch-metrics`.

1. Rename the existing panel "Auto-compact threshold" to "Auto-compact setting (configured)". Its description says it
   is the value from `docs/metrics/context-window-experiment.md` and may not take effect (a setting above the session's
   context window is ignored).
2. Add a stat panel beside it, "Observed compaction point", with
   `k3dm_claude_compaction_pre_tokens_sum{window="$window",trigger="auto"} / k3dm_claude_compactions{window="$window",trigger="auto"}`
   (unit: short, so 168000 reads 168 K). Description: the mean context size at automatic compactions in the window,
   from transcript `compactMetadata.preTokens`, which is the threshold that actually applied. When the window has no
   automatic compactions, the panel shows "No auto-compactions in window" instead of NaN or a blank.
3. Keep the panel grid valid: no overlaps. Neighbouring panels may move or narrow.

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`
- `CHANGELOG.md`

## What NOT to do

- Do not change `bin/k3dm-dispatch-metrics`, the experiment log or `.claude/settings.json`.
- Do not remove the configured-value panel; the gap between the two panels is the point.
- Do not edit `scripts/tests/fixtures/agent-dispatch-dashboard-pre-split.yaml` (a historical fixture).

## Acceptance

```yaml
must:
  M1: the agent-activity dashboard has a panel titled "Auto-compact setting (configured)" querying k3dm_claude_auto_compact_tokens, and no panel titled exactly "Auto-compact threshold"
  M2: the dashboard has a panel titled "Observed compaction point" whose query divides k3dm_claude_compaction_pre_tokens_sum by k3dm_claude_compactions, both filtered to trigger="auto" and window="$window"
  M3: the observed panel maps an empty or NaN result to the text "No auto-compactions in window"
must_not:
  N1: no panel overlaps another in the grid, and the dashboard JSON stays valid
  N2: the observed panel never queries k3dm_claude_auto_compact_tokens (it must not fall back to the configured value), and the configured panel's description never calls itself the effective threshold
evidence:
  E1:
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    intent: >-
      You will see agent_dispatch_dashboard.bats parse the ConfigMap's dashboard JSON, find both panels by title,
      assert their exprs and the NaN/empty mapping, check that no two gridPos rectangles intersect, and that the
      observed panel's expr does not contain k3dm_claude_auto_compact_tokens. Run against the pre-fix YAML, M1-M3 fail.
    what: bats scripts/tests/plugins/agent_dispatch_dashboard.bats
  E2:
    proves: [M1, M2]
    kind: live
    intent: >-
      You will see, after the operator runs make platform-ops on the M5, the dashboard show "Auto-compact setting
      (configured) 200 K" beside "Observed compaction point" at about 168 K for the 7d window, matching the Prometheus
      query of sum / count on the hub.
    what: operator runs make platform-ops; Claude queries Prometheus on the M5 and the operator reads the panel
interface:
  - scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml (ConfigMap with dashboard JSON)
  - Prometheus metrics k3dm_claude_auto_compact_tokens, k3dm_claude_compactions, k3dm_claude_compaction_pre_tokens_sum
```
