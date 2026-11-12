# Bug: Agent Dispatch "Per spec" shows Acting coordinator "not recorded" for tasks that had no handoff

**Status:** OPEN
**Priority:** P3
**Classified:** P3 by gemini-4-argon-medium, 2026-11-12 (Cosmetic dashboard label ambiguity ("not recorded" instead of "no handoff") when the adjacent Handoffs column already shows `0`); Claude proposed P3. Agreed.
**Triage:** passed over (v1.43.16 was not cut; this does not count as a pass-over: it was picked 2026-11-09) — grooming 2026-11-12, operator.
**Waiting on:** operator decision — since 2026-11-12
**Introduced by:** `32393e17` (v1.43.9, Acting coordinator column)
**Should have been caught by:** spec
**Severity:** low — display only; reads as missing data when nothing is missing
**Approval:** operator, 2026-11-08 ("let's do 1 and 2")
**Filed:** 2026-11-08
**Detected by:** operator, asking what "not recorded" means on the Per spec table; cause traced by Claude
**Affected:** `bin/k3dm-dispatch-metrics` (`:980-983`, `:1700`), `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml` (Per spec, Acting coordinator mapping, `:844-845`)
**Branch:** `k3d-manager-v1.43.16` (operator, 2026-11-09)

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
