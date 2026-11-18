# A resolve seen during a Hermes approval re-sample skips the withdrawal and resolved notice

**Status:** OPEN — captured 2026-11-18 from Argon's blind review of PR #163 (v1.44.2), verified by Claude
**Priority:** P3 — rare timing window
**Introduced by:** pre-existing in shape; `withdraw_on_resolve` (v1.44.x R7) kept the default on re-samples by design
**Should have been caught by:** spec
**Introducing change reviewed:** no
**Waiting on:** operator decision
**Prior art:** docs/bugs/2026-11-17-hermes-r7-signing-restore-offered-when-vault-sealed.md (keyword) — read; its test 13 deliberately keeps pending repairs on an approval re-sample. Different question (what happens to the resolved notice). `make find-similar-docs` not run (vector store unreachable).
**Filed:** 2026-11-18

## Symptom

`_run_cycle` defaults `withdraw_on_resolve=False` (`bin/k3dm-hermes:275`). The approval re-samples (`:333` in
`_drain_approvals`, `:1113-1116` in CLI `approve`) use the default. If the incident resolves exactly during a
re-sample, that cycle consumes the `resolved` event without withdrawing pending proposals or posting the resolved
notice, and the next `_poll` sees no transition.

## Impact

A stale proposal can stay pending until it expires, and the "resolved" message is not posted. Approval itself still
refuses correctly.

## Fix sketch

Do not consume the correlator's transition on a re-sample, or replay it on the next `_poll`. Test: resolve during a
re-sample, then `_poll` posts the withdrawal; a re-sample without a resolve leaves pending intact (control, existing
test 13).

## Fable confirmation (2026-11-18)

Fable found the same (its #5) independently, adding that the approval still executes after the resolve and `test_resolved_keeps_pending_on_approval_resample` pins this without asserting what approve does next.
