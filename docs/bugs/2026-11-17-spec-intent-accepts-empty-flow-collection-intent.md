# spec-intent gate accepts `intent: []` or `intent: {}` as an operator-facing intent

**Status:** OPEN — captured 2026-11-17 from Argon's blind review of PR #162 (v1.44.1), verified by Claude
**Priority:** P3 — needs an author to write an empty collection; the gate then lets an evidence item through with no intent
**Introduced by:** d09d98f2 (spec-intent flow-style fix, k3d-manager-v1.44.1)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Minor validation hygiene gap where `spec_intent.py` accepts empty YAML flow collections (`[]` or `{}`) as non-empty intent strings.)
**Waiting on:** operator decision
**Prior art:** none above threshold. Exact slug: no match; keyword grep of docs/bugs: no match. `make find-similar-docs` not run (vector store unreachable from this machine: no k3d-k3d-cluster context).
**Filed:** 2026-11-17

## Symptom

`scripts/lib/spec_intent.py` treats any non-empty value other than `null` or `~` as an intent, so `- {id: E1, proves: [x], kind: offline, intent: []}` passes `check()`.

## Verified by Claude (2026-11-17)

A scratch spec with that one evidence item: `spec_intent.check()` returned `[]` (no errors). Argon's second claim, that a doubled `''` inside a single-quoted flow value breaks parsing, was refuted: `_flow_fields` parsed it correctly.
