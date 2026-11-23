# Hermes approval re-propose overwrites the pending proposal, so the digest and expiry checks never fire

**Status:** OPEN — captured 2026-11-18 from Fable's blind diff review of PR #163 (v1.44.2), verified by Claude
**Priority:** P3 — defence-in-depth gap; seal safety holds through the precondition
**Introduced by:** pre-existing (approval flow on `main`)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Defense-in-depth flaw where re-running a cycle before approval overwrites the pending proposal's digest and expiry timestamp while preconditions still hold.)
**Waiting on:** operator decision
**Prior art:** docs/bugs/2026-11-18-hermes-resolve-during-approval-resample-skips-withdraw.md — read; same re-sample call, different defect. `make find-similar-docs` not run (vector store unreachable).
**Filed:** 2026-11-18

## Symptom

Both approve paths (`bin/k3dm-hermes:333` in `_drain_approvals`, `:1113` in CLI `approve`) call `_run_cycle(state)` before
`repairs.approve`. `_run_cycle` calls `propose()`, which writes `pending[action_id] = proposal` (`repairs.py:373`) with a
fresh `records_digest` and `expires_at`. `approve()`'s "sensor records changed since proposal" and "proposal expired"
checks (`repairs.py:~399`) therefore compare against a proposal made a moment ago. Fable's probe: changed vault pod data
→ bare `approve()` refused; after the re-propose, `executed`. `test_r7_digest_covers_vault_seal` guards a check that is
dead in the real flow.

## Fix sketch

In `propose()`, keep an existing non-expired pending entry (do not overwrite digest/expiry). Test: approve after a records
change through `_drain_approvals` → refused.
