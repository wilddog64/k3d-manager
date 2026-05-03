# Retrospective — PR #35: payment-service DB auth failure fix

**Date:** 2026-05-03
**Milestone:** payment-service CrashLoopBackOff — ArgoCD/ESO credential conflict
**PR:** #35 — merged to main (`65c92057`)
**Participants:** Claude, Codex, Copilot

## What Went Well

- Root cause diagnosis was fast: Flyway error → secret inspection → ArgoCD selfHeal race identified in one session
- Copilot caught a substantive technical gap (missing `RespectIgnoreDifferences=true` + `/metadata/ownerReferences`) that made the fix meaningfully more complete
- Codex applied the YAML fix cleanly on first attempt — spec old/new blocks matched exactly, no drift
- The spec + verify pattern held: Claude verified the old block against the actual file before approving, catching no discrepancies

## What Went Wrong

- **Premature branch creation**: initial diagnosis misread a cached version of `postgres-payment-externalsecret.yaml` and assumed RABBITMQ keys were missing (already fixed in PR #28). A branch `bug/payment-service-rabbitmq-credentials` was created then deleted — wasted a cycle
- **`payment-db-credentials-eso` not in any repo**: configuration drift from a previous sandbox session. The imperative ESO was not codified and represents an ongoing cleanup item
- **Dead reference in spec doc**: "What NOT to Do" section referenced a non-existent `...-tracking.md` file — Copilot caught it; spec template should require self-contained references only
- **`RespectIgnoreDifferences=true` not in initial spec**: the fix was logically incomplete without it — `ignoreDifferences` alone suppresses the diff indicator but doesn't prevent overwrites on explicit sync; this should be standard knowledge for any ESO/ArgoCD ignoreDifferences pattern

## Process Rules Added

| Rule | File | Rationale |
|------|------|-----------|
| When adding `ignoreDifferences` for an ESO-managed resource, always pair with `RespectIgnoreDifferences=true` in `syncOptions` | CLAUDE.md / future spec templates | Without it, ArgoCD still overwrites on explicit syncs |
| Bug doc "What NOT to Do" section must only reference files that exist in the repo | spec template | Dead references mislead Codex and Copilot |

## Decisions Made

- **`ignoreDifferences` scope**: guard both `/data` and `/metadata/ownerReferences` — ESO sets ownerReferences as part of `creationPolicy: Owner`; leaving it unguarded causes drift
- **Imperative `payment-db-credentials-eso` cleanup**: deferred to post-merge manual step (after ArgoCD syncs with new ignoreDifferences, delete the imperative ESO to restore clean ownership)
- **`docs/next-improvements` branch**: force-forwarded to PR #35 merge SHA (it was stranded at PR #34 retro commit `6fd9437`)

## Theme

A quiet but persistent credential conflict: ArgoCD's `selfHeal` was overwriting the Vault-seeded password back to `CHANGE_ME` every few minutes, consistently winning the race against ESO's 24-hour refresh. The fix is a two-line YAML addition — but Copilot correctly identified that without `RespectIgnoreDifferences=true`, the protection would be incomplete. The session also surfaced an imperative `payment-db-credentials-eso` that was never committed to the repo, a reminder that sandbox operations leave configuration drift that only shows up as bugs later.
