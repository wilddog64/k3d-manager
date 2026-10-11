# Bug: every DR drill overwrites the host cluster's Vault unseal cache

**Filed:** 2026-10-11
**Branch:** `k3d-manager-v1.43.1`
**Status:** OPEN — fix before the credential guard flips to `enforce`
**Priority:** P2 — the host Vault can still be unsealed by hand; nothing is lost from a running Vault
**Severity:** high — the cached shards for the host Vault are replaced with a throwaway Vault's shard

## Symptom

The first audit-mode drill with the credential guard (M2, result `20261011T205152Z.json`, at
`84b26ca2`) passed V0–V7 and reported five `credentials_unexpected` entries, all against the
M2's own unseal cache:

| op | service | account |
|---|---|---|
| find, add, delete | `k3d-manager-vault-unseal` | `secrets/vault:count` |
| add, delete | `k3d-manager-vault-unseal` | `secrets/vault:shard1` |

On the M2, `k3d-k3d-cluster` runs Vault as `secrets/vault`, the same account. Its `vault-0` has
been `Ready=False` (sealed) since 2026-07-20, so the drill did not cause an outage, but every drill
since the first one has cleared that Vault's cached shards and written the drill Vault's single
shard in their place. An auto-unseal of the M2 Vault from the cache now uses a key that belongs to
a deleted cluster.

## Root cause

Phase 2 of `bin/dr-drill` builds the drill hub with `bin/hub-up` (`bin/dr-drill:245-249`). Its
Vault deploy calls `_vault_cache_unseal_keys` (`scripts/plugins/vault.sh:1749`), which writes
`k3d-manager-vault-unseal` keyed by `<namespace>/<release>` only
(`scripts/plugins/vault.sh:290`). Nothing in the key says which cluster, so a fresh `vault/vault`
or `secrets/vault` on any cluster replaces the host's entry. The same literal is used by
`_vault_replay_cached_unseal` (`:573`) and `_vault_purge_unseal_cache` (`:793`).

The drill isolates the kubeconfig, cluster name and context; it never isolated the Keychain.

## Fix

1. `scripts/plugins/vault.sh`: the three `local service="k3d-manager-vault-unseal"` lines become
   `local service="${VAULT_UNSEAL_CACHE_SERVICE:-k3d-manager-vault-unseal}"`. The default is
   unchanged, so nothing outside the drill moves.
2. `bin/dr-drill`: the phase 2 `export` line adds
   `VAULT_UNSEAL_CACHE_SERVICE=k3dm-vault-unseal-drill`. Teardown clears that service's
   `count`/`shardN` entries (best effort, never fails teardown), so a drill leaves nothing behind.
3. `scripts/etc/dr/credential-allowlist.tsv`: `drill` scope gains `find`, `add` and `delete` on
   `k3dm-vault-unseal-drill` `secrets/vault:*`. `k3d-manager-vault-unseal` stays
   out of the `drill` scope, so once the guard is in `enforce` a regression is refused (exit 44)
   instead of recorded.

## Tests

- `_vault_cache_unseal_keys` with `VAULT_UNSEAL_CACHE_SERVICE` set stores and clears only that
  service (stubbed `_secret_store_data`/`_secret_clear_data`/`_secret_load_data` call log); unset,
  it still uses `k3d-manager-vault-unseal`.
- `bin/dr-drill` exports `VAULT_UNSEAL_CACHE_SERVICE=k3dm-vault-unseal-drill` before `hub-up`, and
  teardown clears it.
- Shim, scope `drill`, `enforce`: `add-generic-password -s k3d-manager-vault-unseal` exits 44;
  `-s k3dm-vault-unseal-drill` passes.
- Mutation: drop the export in `bin/dr-drill` → the export test is red.

## Proof it works

The next audit drill on the M2 reports `credentials_unexpected: []`. Then the guard flips to
`enforce` and an enforce drill reports V9 true.

## Operator follow-up (not code)

The M2 Vault (`k3d-k3d-cluster`, `secrets/vault`) is sealed and its cached shards are gone. If it
is still wanted, unseal it from the operator's own record of its keys and re-cache; if not, retire
it. Claude does not touch it.

## What NOT to Do

- Do NOT change the default service name; the hub and the real restore depend on it.
- Do NOT read or print a shard value in a test or a log.
- Do NOT run a drill from a test.
