# Hermes 'Root cause: Vault sealed' card still recommends approving r3/r4, and Withdrawn lists unshown repairs

**Status:** OPEN — captured 2026-11-18 from Fable's blind diff review of PR #163 (v1.44.2), verified by Claude
**Priority:** P3 — operator-facing card contradiction
**Triage:** backlog — pull into a release that already touches `bin/k3dm-hermes` (operator, 2026-11-25); Argon blind classification, Claude verified
**Introduced by:** fadf8438 (root-cause and Recommended lines, v1.44.2)
**Should have been caught by:** spec
**Introducing change reviewed:** yes (Fable spec review)
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Cosmetic and UX contradiction on Hermes Slack cards where a sealed-Vault root-cause card still prints `Recommended: Approve` for r3/r4 and lists unshown withdrawn repairs.)
**Waiting on:** operator decision
**Prior art:** none above threshold. Exact slug: no match; keyword grep of docs/bugs: no match. `make find-similar-docs` not run (vector store unreachable from this machine: no k3d-k3d-cluster context).
**Filed:** 2026-11-18

## Symptom

With Vault sealed, the correlator text (`scripts/lib/hermes/correlator.py:57-64`) says every other failure follows from the
seal and "nothing to approve unless Vault is still sealed after 15 minutes". `_run_cycle` then appends `Recommended:
Approve — …` for r3/r4, which are not seal-gated (only r7 is), so one card says both. Also, `propose()` stores proposals
every cycle, not only on cards, so a "Withdrawn: …" line can list repairs the operator never saw, and a CLI `approve <id>`
still works after "Nothing to approve" when the precondition holds again.

## Fix sketch

While `vault_seal` is degraded, suppress the Recommended line (or gate r3/r4 on unsealed Vault too); list in Withdrawn only
proposals that were posted. Tests: sealed + r3 precondition → no Recommended line.
