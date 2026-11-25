# Hermes `vault_seal` reports unknown when any Vault pod lacks a valid seal label

**Status:** OPEN — captured 2026-11-18 from Argon's blind review of PR #163 (v1.44.2), verified by Claude
**Priority:** P3 — matches the H1 spec; the hub runs one Vault pod
**Triage:** backlog — pull into a release that already touches `scripts/lib/hermes/sensors.py` (operator, 2026-11-25); Argon blind classification, Claude verified
**Introduced by:** v1.44.2 Hermes vault_seal sensor (`scripts/lib/hermes/sensors.py:905`)
**Should have been caught by:** spec
**Introducing change reviewed:** no
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Latent multi-pod sensor edge case where an unlabelled Vault pod causes `vault_seal` to return `unknown`, with no impact on the single-pod hub.)
**Waiting on:** operator decision
**Prior art:** none above threshold. Exact slug: no match; keyword grep of docs/bugs: no match. `make find-similar-docs` not run (vector store unreachable from this machine: no k3d-k3d-cluster context).
**Filed:** 2026-11-18

## Symptom

`vault_seal` (`scripts/lib/hermes/sensors.py:905`) returns `unknown` if any pod's `vault-sealed` label is missing or
not `true`/`false`. The webhook (W3 fix) instead treats such a pod as unavailable and still reports a sealed peer.

## Impact

With more than one Vault pod, an unlabelled pod would hide a sealed one from Hermes. The hub runs a single pod, so no
effect today.

## Fix sketch

Mirror the webhook: ignore pods without valid labels unless none has them. Test: vault-0 `true`, vault-1 unlabelled
→ sealed; all unlabelled → unknown (control).

## Fable confirmation (2026-11-18)

Fable adds two related points: (a) any one sealed pod counts as sealed in both components, so an active unsealed leader plus a sealed standby short-circuits every webhook alert (`bin/k3dm-webhook:2092`, `sensors.py:917`); (b) a pod with only `vault-sealed=true` is "state unavailable" in the webhook (needs all three labels, `:2075-2078`) but sealed in Hermes. Both harmless on the single-replica hub.
