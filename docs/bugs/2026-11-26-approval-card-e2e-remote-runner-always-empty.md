# Bug: the approval card for `make-e2e-remote` never shows the runner name

**Status:** OPEN — captured, not triaged
**Priority:** P2 (proposed) — the operator approves a remote e2e run without seeing which runner it targets
**Introduced by:** v1.46.0 plan 1 part A (`358f10b9`, `scripts/lib/webhook/cloud_approval.py`)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-26
**Classified:** pending (Argon, from this doc alone)
**Prior art:** exact-slug glob: none; related captures on approval card wording (2026-11-25, "with none", "Run Run") are different strings; `make find-similar-docs` not run
**Severity:** medium — a gated action's card hides its one variable argument; the deny/approve decision is made blind on that point
**Filed:** 2026-11-26, found by Neon in the blind review of v1.46.0 plan 2 (`v1460-plan2-review-neon`); Claude confirmed in code
**Component:** `scripts/lib/webhook/cloud_approval.py:160` (`card`)

## Symptom (from code, not yet seen live)

`card()` reads `request.get('args', {}).get('runner', '')` (lowercase), but the allowlist defines the argument as
`RUNNER` (`scripts/lib/webhook/cloud_actions.py:38`, `{"RUNNER": RUNNER_RE}`), so the card always renders
"runs the e2e suite on runner " with an empty name.

## Fix (for triage)

Read `RUNNER` (the allowlist key), and add a test that a `make-e2e-remote` card contains the runner value; red on current code.
Live: one gated `make-e2e-remote` request, read the card, deny.
