# Bug: Agent Activity "Sessions by mode" shows a "Value" bar that sums the category series

**Status:** OPEN — captured 2026-11-21
**Priority:** P3 (cosmetic but misleading: an extra bar roughly equal to the exec count; exec and interactive bars are right)
**Introduced by:** aa1196ed (v1.43.15 added `k3dm_codex_sessions{window,category}` under the same metric name the v1.43.6 panel groups by `mode`)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-21
**Prior art:** exact-slug glob none; `ls docs/bugs | grep -iE 'sessions-by-mode|value-bar|codex-sessions'` none; `make find-similar-docs` not run (vector store unavailable on the M4 earlier today)
**Branch:** `k3d-manager-v1.45.0` (target set at triage)

## Symptom

Operator screenshot 2026-11-21 18:3xZ (`docs/captures/2026-11-21-codex-row-float-up-e2/agent-activity-codex-row.png`), Grafana
`/d/k3dm-agent-activity`, row "All Codex activity", panel 55 "Sessions by mode", window 7d: bars exec 155, **Value 156**, interactive 1.

## Cause

`bin/k3dm-dispatch-metrics` writes two series shapes under one metric name:

- `:2124` `k3dm_codex_sessions{window,mode,repo}` (what the panel means to count);
- `:2096` `k3dm_codex_sessions{window,category}` (dispatch, dispatch_unrecorded, exec_untracked, guardian, interactive, other).

Panel 55 (`grafana-dashboard-agent-activity.yaml:518`) queries `sum by (mode) (k3dm_codex_sessions{window="$window"})`. The category series
have no `mode`, so they sum into one series with an empty `mode`, which Grafana labels "Value". Hub Prometheus, Claude read-only
2026-11-21: 7d category values 0+2+67+21+65+1+0 = 156, the "Value" bar; 7d mode=exec series sum to 155, the exec bar.

The only other reader, Agent Cost `grafana-dashboard-agent-cost.yaml:377`, filters `category="dispatch_unrecorded"` and is correct.

## Workaround

Ignore the "Value" bar.

## Fix direction (for triage)

Smallest: panel 55 selects `mode!=""` (`sum by (mode) (k3dm_codex_sessions{window="$window",mode!=""})`) plus a bats assertion that every
`sum by (<label>)` over a metric with mixed series shapes filters that label non-empty. Larger, a contract change: rename the category
series to their own metric (readers: agent-cost :377, exporter tests).
