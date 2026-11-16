# Bug: Vault tokens and a ServiceAccount JWT passed in `kubectl exec` argv (`test_eso`, `test_vault` login, `bin/get-ldap-password`)

**Status:** OPEN — captured 2026-11-15
**Priority:** P2 (proposed: A02 security-rule violation; tokens visible in process lists on the host and in the pod, and under xtrace; dev/test paths, no known leak)
**Introduced by:** pre-existing
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-15
**Triage:** patch → v1.44.1; Claude's P2 kept over Argon P3 (breaks the CLAUDE.md secrets rule) — operator grooming 2026-11-15 ("Accept as shown")
**Prior art:** exact-slug pass, no match; `find-similar-docs` not run (needs context k3d-k3d-cluster from the M4) — found by the Fable spec review of `2026-11-15-vault-pod-restart-invalidates-token-reviewer-jwt-eso-403.md`, which fixes the `test_vault` root-token sites only

## What is wrong

CLAUDE.md security rules: no Vault tokens in arguments or `kubectl exec` strings (use env or stdin). These sites
still put a token value into the `sh -c` argument:

- `scripts/lib/test.sh:583` (`test_eso` EXIT trap string embeds the root token), `:587` (`vault kv put`), `:661`
  (`_cleanup_eso_test`, `vault kv delete`) — root token.
- `scripts/lib/test.sh:792-793` — ServiceAccount JWT in `vault write auth/kubernetes/login ... jwt=$sa_jwt`; `:796` —
  the Vault token from that login in `VAULT_TOKEN=$vault_token`.
- `bin/get-ldap-password:131-132`, `:137-138`, `:142-143` — `VAULT_TOKEN='$VAULT_TOKEN'` in three `kubectl exec` calls.

## Fix direction

The stdin pattern from `_hub_data_repoint_vault` (`read -r VAULT_TOKEN; export VAULT_TOKEN; ...`); for the login,
send the JWT on stdin (`jwt=-` reads it from stdin in the Vault CLI — prove on Vault 1.20.1 before dispatch). Batch with
any other `test.sh` P2/P3 work by file.
