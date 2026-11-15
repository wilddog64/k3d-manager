# Bug: spec-intent gate never checks evidence items written in YAML flow style

**Status:** OPEN — captured 2026-11-15
**Priority:** P3 (proposed: a gate that silently passes; no wrong dispatch known)
**Introduced by:** unknown (`scripts/lib/spec_intent.py`)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-15
**Prior art:** exact-slug pass, no match; `find-similar-docs` not run (needs context k3d-k3d-cluster) — none known

## What happened (Claude, 2026-11-15)

`scripts/lib/spec_intent.py:50` splits evidence items on `^\s*-\s+id\s*:` (block style). Items written as flow
mappings (`  - {id: E1, proves: [...], kind: offline, intent: "..."}`, used by many specs, for example
`docs/bugs/2026-11-10-ci-job-named-lint-runs-the-full-test-suite.md`) never match, so a flow-style item with no
`intent` passes the gate. Found while dispatching the ESO spec; that spec was converted to block style.

Also: the header regex at `:72-74` requires the `**Intent approved:**` line to end at the date, so a trailing note
(`operator, 2026-11-15 ("approved")`) is refused with "missing header", a misleading message.

## Fix direction

Parse the Acceptance block as YAML (or accept both item styles) and check `intent` on every evidence item; name the
trailing-text case in the refusal message. Test with a flow-style item lacking intent (red on today's code).
