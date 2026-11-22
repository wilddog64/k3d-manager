# `_hub_recovery_sync_vault_root_token` passes the Vault root token to `jq --arg` (visible in ps)

**Status:** OPEN — captured 2026-11-18 from Fable's blind diff review of PR #163 (v1.44.2), verified by Claude
**Priority:** P3 — security rule violation (A02), local host only, short-lived process
**Introduced by:** pre-existing (`scripts/plugins/hub_recovery.sh:75` on `main`)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Classified:** P3 by gemini-4-argon-medium, 2026-11-22 (Security hygiene rule violation where the Keychain fallback passes the Vault root token via `jq --arg` argv instead of stdin.)
**Waiting on:** operator decision
**Prior art:** none above threshold. Exact slug: no match; keyword grep of docs/bugs: no match. `make find-similar-docs` not run (vector store unreachable from this machine: no k3d-k3d-cluster context).
**Filed:** 2026-11-18

## Symptom

On the Keychain fallback path, `scripts/plugins/hub_recovery.sh:75` runs
`jq -n --arg root_token "$root_token" '…'`, putting the root token in `jq`'s argv, readable by any local user via `ps`
while it runs. CLAUDE.md: "no Vault tokens in arguments … (use env or stdin)". `_hub_data_repoint_vault` already does it
right: `printf '%s' "$root_token" | jq -Rs '…'`. The repoint calls this function as its last step.

## Fix sketch

Same stdin pattern as hub_data. Test: stub `jq` records its argv; assert the token is absent and the Secret payload has it.
