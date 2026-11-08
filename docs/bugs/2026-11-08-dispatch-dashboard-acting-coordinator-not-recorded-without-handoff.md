# Bug: Agent Dispatch "Per spec" shows Acting coordinator "not recorded" for tasks that had no handoff

**Status:** OPEN
**Priority:** P3
**Waiting on:** dispatch — since 2026-11-08 (batch with the Agent column P3; both edit the Per spec panel)
**Introduced by:** `32393e17` (v1.43.9, Acting coordinator column)
**Should have been caught by:** spec
**Severity:** low — display only; reads as missing data when nothing is missing
**Approval:** operator, 2026-11-08 ("let's do 1 and 2")
**Filed:** 2026-11-08
**Detected by:** operator, asking what "not recorded" means on the Per spec table; cause traced by Claude
**Affected:** `bin/k3dm-dispatch-metrics` (`:980-983`, `:1700`), `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml` (Per spec, Acting coordinator mapping, `:844-845`)
**Branch:** `k3d-manager-v1.43.15`

## Symptom

Every row in the Per spec table shows Acting coordinator "not recorded", and every row shows Handoffs `0`.

## Root cause

The acting coordinator is the identity on the latest `handoff` event. With no handoff, the exporter falls back to
`{"vendor": "unknown", ...}` (`bin/k3dm-dispatch-metrics:981-983`), the same value it uses when a handoff happened
but its identity was not captured. The dashboard maps `unknown` to "not recorded" (`:844-845`). So "this task had
no handoff" and "a handoff was not captured" look identical. The ledger had no `handoff` events on 2026-11-08, so
every row reads "not recorded".

## Fix direction

Tell the two cases apart: with zero handoffs, show "no handoff" (or blank); keep "not recorded" for a handoff
whose identity is unknown. Update the panel description sentence about Acting coordinator to match. An
Acceptance block, with a paired test for each case, is written before dispatch.
