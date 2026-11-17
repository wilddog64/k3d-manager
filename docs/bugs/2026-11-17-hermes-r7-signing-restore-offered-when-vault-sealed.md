# Bug: Hermes offers the cosign signing-restore repair (r7) when every ExternalSecret fails because Vault is sealed

**Status:** OPEN
**Priority:** P3 (proposed: the repair waits for operator approval, so nothing runs unasked; a wrong approval would rewrite the signing key path and policy for no reason)
**Introduced by:** pre-existing
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-17
**Prior art:** `docs/bugs/2026-10-12-hermes-has-no-vault-sealed-sensor.md` (exact-slug pass; `find-similar-docs` not run, no k3d-k3d-cluster context on the M4) — read, related root cause (no sealed-Vault signal), different symptom (wrong repair offered)
**Filed:** 2026-11-17

## What happened

At 01:09Z on 2026-11-17 Vault on the hub was sealed by a planned restart (watchdog live check, operator go). Hermes posted an incident to Slack: `eso: Ready=False; 19/20 not synced: cosign-public-key, ghcr-pull-secret, ghcr-pull-secret`, plus two ArgoCD apps Degraded, and offered **r7 "Restore cosign signing key and ESO grant"** (`make signing-restore`) with Approve / Deny buttons. The same window produced two Gemini ArgoCDAppDegraded diagnoses (shopping-cart-apps, shopping-cart-identity) that blamed an App-of-Apps misconfiguration and Keycloak probes; neither mentioned Vault.

After the watchdog unsealed Vault (01:25:28Z), every ExternalSecret on the hub and on ubuntu-hostinger (20/20) was Ready and every ArgoCD application was Synced/Healthy by 01:28Z, with no repair run.

## Cause

`scripts/lib/hermes/repairs.py:195-199` `_r7_precondition` fires when the `eso` sensor is degraded, its evidence contains `cosign-public-key`, and that lasts two cycles. When Vault is sealed, every ExternalSecret fails, so `cosign-public-key` is always in the evidence list. r7 cannot tell "the cosign key is missing" from "Vault is unavailable".

## Fix direction (to spec at triage)

r7 should not be offered when most ExternalSecrets fail at once or when Vault reports sealed. Link to the vault-sealed sensor bug above: with that sensor, r7 (and the LLM diagnoses) could be suppressed while Vault is sealed.
