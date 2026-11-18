# Plan dashboard shows "ready on your go" for plans whose spec is still a draft

**Status:** OPEN
**Priority:** P3
**Introduced by:** unknown
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-18
**Prior art:** none (`make find-similar-docs` unavailable: vector store context `k3d-k3d-cluster` missing; exact-slug glob found nothing) — not run

## Symptom

Operator, 2026-11-18, screenshot of the v1.45.0 plans table: plans 1 (remote promote approval), 4 (browser SSH console)
and 5 (dispatch stall recovery) all show **Blocked by: ready on your go** and **⚠ needs your decision**, so it looks as
if three plans wait on the operator. None does yet:

- Plan 1 is `DRAFT`: proof of Slack/Workers behaviour and the Fable + Astra spec review are still owed by Claude.
- Plan 4 is `DRAFT`: refresh and the critical-risk spec review are owed by Claude.
- Plan 5 is `PLANNED`: the spec is not written, and its intent is `**Intent approved:** no`.

## Cause (read from code, not run)

`bin/k3dm-vectordb-metrics:497-531` builds `blocked_by` from branch, dependencies, wave note, intents and file overlaps,
and falls through to "ready on your go" when the `**Dispatch:**` header is not `go`. It never reads the `**Status:**`
first word, so a `DRAFT` or `PLANNED` spec counts as dispatchable.

`intent_required` (`:414`) is true only when a `**Filed:**` line exists with date >= 2026-11-08. Plan 5 has no Filed line
and plan 4 was filed 2026-10-25, so neither shows "intents need approval" even though plan 5's intent is `no`.

## Proposed fix (for triage)

Add a blocker from the Status first word: `DRAFT` → "spec not reviewed", `PLANNED` → "spec not written". Treat
`**Intent approved:** no` as unapproved regardless of the Filed date.
