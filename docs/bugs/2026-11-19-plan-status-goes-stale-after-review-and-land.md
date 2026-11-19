# Plan dashboard shows landed and reviewed plans as "dispatched" or "spec not reviewed" because plan Status is updated by hand

**Status:** OPEN — spec `docs/plans/plan-status-auto-land-and-precommit.md` written; operator said "go with your suggestion" (2026-11-19)
**Priority:** P3 — the dashboard misleads, but the plan files and the dispatch ledger are right; workaround: fix the Status line by hand
**Introduced by:** pre-existing
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Waiting on:** dispatch — since 2026-11-19
**Triage:** operator, 2026-11-19 ("file one and go with your suggestion"): fix 1 (land writes Status) + fix 2 (pre-commit refuses DRAFT with approved intent); Argon rev-1 review narrowed fix 2 (no "landed"-word rule: umbrella plans)
**Prior art:** `docs/bugs/2026-11-18-plan-dashboard-ready-on-your-go-ignores-draft-status.md` (exact-slug pass; `make find-similar-docs` unavailable: vector store context missing) — read, different root cause: that fix made `DRAFT` show "spec not reviewed", which is correct; this bug is the Status line itself going stale

## Symptom

Operator screenshot of the v1.45.0 plans table, 2026-11-19 afternoon:

- "Remote promote, part 1" showed **dispatched / proposed**. It landed at 07:28 as `643747e5`.
- "Remote promote approval" (plan 1) and "Browser SSH console" (plan 4) showed **spec not reviewed**. Both specs went
  through four Fable + Astra review rounds, and the operator approved intent (2026-11-18 and 2026-11-19).

Claude corrected the Status lines by hand in `23818ae4`.

## Cause

The dashboard (`bin/k3dm-vectordb-metrics:388-393`, `_plan_state` at `:264`) reads the first word of each plan's
`**Status:**` line. Nothing updates that line when the state changes:

- `bin/k3dm-codex-dispatch land` (`_dispatch_land`, ends at `:1552`) merges and writes the ledger `land` event, but leaves the
  spec's Status at whatever it was at dispatch, usually `DRAFT vN` or `READY`.
- Nothing stops a commit that carries `**Intent approved:** operator, <date>` with a Status that still starts `DRAFT`. Intent
  is approved only after review, so that combination is always stale.

## Fix

Spec: `docs/plans/plan-status-auto-land-and-precommit.md`.
