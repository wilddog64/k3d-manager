# dispatch-metrics: Astra 6.2 runs show as model `unknown` and cost $0

**Status:** OPEN — captured 2026-11-18 while dispatching the first Astra review (lib-foundation PR #89)
**Priority:** P3 — reporting only; tokens and run time are still exported
**Introduced by:** pre-existing (codex added `gpt-6.2-astra` and `gpt-6.2-sol`; the allowlist and price file were never updated)
**Should have been caught by:** none
**Introducing change reviewed:** no
**Waiting on:** operator decision — since 2026-11-18 (Astra 6.2 rates and source; dispatch timing)
**Prior art:** `docs/bugs/2026-11-10-agent-cost-shows-unpriced-claude-model-as-zero.md` (exact-slug review) — read, different root cause (Claude price); `docs/bugs/2026-11-16-dispatch-metrics-xhigh-tier-runs-unpriced.md` — read, different root cause (tier suffix not stripped). `make find-similar-docs` not run (vector store unreachable, 2026-11-18).
**Filed:** 2026-11-18
**Approval:** operator, 2026-11-18: "go ahead to file P3 bug" (after Claude reported the two gaps below)

## Symptom

The operator is trialling Astra (OpenAI, run through codex) for spec and bug review, comparing its findings and cost
with Argon and Fable. Dispatch `lf-v057-review-astra` (2026-11-18) recorded `agent: codex`, `model: gpt-6.2-astra`,
`model_source: explicit` in the ledger. On the Agent Dispatch dashboard:

- **Model identity** shows `unknown`: `MODEL_IDENTITY_ALLOWLIST` (`bin/k3dm-dispatch-metrics:41-47`) lists `gpt-6-astra`
  but not `gpt-6.2-astra` (nor `gpt-6.2-sol`); `:1865` maps any name not on the list to `unknown`.
- **Cost** is $0: `scripts/etc/agent/codex-model-prices.json` prices only `gpt-5.6-luna`, `gpt-6-luna`, `gpt-6.1-sol`,
  `gpt-6.1-terra` among OpenAI models; `_render_cost` (`bin/k3dm-dispatch-metrics:~2057`) gives an unpriced model 0.

The trial's question is whether Astra's cost is worth its findings, so the cost panel is the part that matters.

## Fix (proposed; spec to follow once rates are known)

1. Add `gpt-6.2-astra` and `gpt-6.2-sol` to `MODEL_IDENTITY_ALLOWLIST`.
2. Add `gpt-6.2-astra` (and `gpt-6-astra`, `gpt-6.2-sol` if rates are known) to `codex-model-prices.json` with
   `input`, `cached_input`, `output` per 1M tokens, and a dated source in its `source` string — rates from the operator
   or a published page, never guessed.
3. Test: a ledger fixture row with `model: gpt-6.2-astra` exports that model name on `k3dm_dispatch_model_identity`
   and a nonzero cost (pre-fix: `unknown` and 0).

The ledger keeps the 2026-11-18 Astra run's tokens, so its cost appears once the fix is live on the hub
(`make hub-promote`).
