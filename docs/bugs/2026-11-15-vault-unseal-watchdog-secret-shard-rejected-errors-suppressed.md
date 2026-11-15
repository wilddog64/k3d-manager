# Bug: hub unseal watchdog replays a shard Vault rejects, and hides the error

**Status:** OPEN — captured 2026-11-15
**Priority:** P2 (proposed: a hub Vault restart stays sealed until the operator runs `deploy_vault --re-unseal` from the Keychain; workaround exists)
**Introduced by:** unknown (the `vault-unseal` Secret was created 2026-10-30T20:52:23Z, around the M5 hub cut-over)
**Should have been caught by:** live check
**Introducing change reviewed:** unknown
**Waiting on:** investigation — since 2026-11-15
**Prior art:** `docs/bugs/2026-10-12-vault-unseal-watchdog-gives-up-while-vault-boots.md` (exact-slug pass; `find-similar-docs` printed nothing) — read, different root cause (that bug is the boot-time retry; its fix ran correctly here)
**Severity:** high when it bites — every Vault restart on the hub (OrbStack update, node reboot) leaves Vault sealed, ESO refreshes fail, and nothing unseals it automatically

## What happened (Claude, 2026-11-15, M5 hub `k3d-k3d-cluster`)

To live-check the 2026-10-12 retry fix, Claude applied the fixed template (`vault_install_unseal_watchdog`) and deleted
`secrets/vault-0` at 15:24:45Z. Watchdog jobs at 15:25, 15:30 and 15:35 each logged `vault sealed — replaying shard`
then `unseal attempt complete (still sealed or unreachable)`. `vault status`: initialized, sealed, `t` 1, progress 0 —
the shard was rejected outright. Vault stayed sealed about 12 minutes. The operator then ran
`./scripts/k3d-manager deploy_vault --re-unseal --namespace secrets` on the M5 (login Keychain unlocked):
`applying 1 cached unseal shard(s)` → `now unsealed`. One ExternalSecret (`cicd/argocd-oidc-secret`) recorded
`SecretSyncedError` at 15:34 during the outage.

## Evidence so far

- SHA-256 prefix of the Secret's `shard-1` (CR/LF stripped): `f1bffbb8cc7e`. The Keychain comparison failed from a
  non-interactive ssh session (empty read), so "the Secret's shard is stale" is still a hypothesis, not proven.
- The Keychain shard opened Vault on the first try, and the Secret's shard did not, which is consistent with a stale Secret.
- `scripts/etc/vault/unseal-watchdog.yaml.tmpl:69`: `vault operator unseal "$(cat "$SHARD_FILE")" >/dev/null 2>&1 || true`
  discards the reason, so job logs cannot tell a bad shard from a network error.
- Side note: when `envsubst` is not on PATH, `vault_install_unseal_watchdog` (`scripts/plugins/vault.sh:1066`) writes an empty
  file and fails at `kubectl apply` with "no objects passed to apply" instead of naming envsubst.

## To investigate

1. On the M5 in a local terminal, compare the hashes of the Keychain `k3d-manager-vault-unseal` shard and the Secret's `shard-1` (never print values).
2. Find who writes the `vault-unseal` Secret and why it did not follow the current shard (cut-over restore? re-init?).
3. Log the unseal failure reason without printing the shard (for example, keep stderr but filter out the argument).
