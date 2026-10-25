# Bug: deploy_vault on a sealed Vault with a rejected unseal cache deletes the unseal key and root token and tries to wipe the data

**Status:** OPEN — dispatched to Luna 2026-10-25
**Priority:** P1
**Severity:** critical — the documented "re-unseal after restart" command deletes the hub's in-cluster unseal key and root token and attempts a data reset; only a host-path lookup miss saved the Raft data on 2026-10-25
**Release:** v1.43.7 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-25, by Claude, from the live hub incident at 05:46 PDT
**Approval:** explicit 2026-10-25 ("please file P1 bug and dispatch to Luna"). Critical (hub Vault); the operator's message is the dispatch go.
**Component:** `scripts/plugins/vault.sh` (`_vault_bootstrap_ha`, `_vault_reinit_from_reset`, `_vault_reset_data_path`), `docs/howto/vault.md`
**Related:** `docs/bugs/2026-10-11-dr-drill-overwrites-host-vault-unseal-cache.md` (an earlier way the host cache came to hold the wrong shard)

## Incident

An OrbStack update stopped the hub VM at 05:36 PDT. After restart Vault came up `Initialized: true`, `Sealed: true`.
The operator ran the documented recovery, `./scripts/k3d-manager deploy_vault --confirm`
(`docs/howto/vault.md`: "Re-unseal after restart … idempotent — safe to re-run"):

1. `_vault_replay_cached_unseal` sent the shard cached in Keychain service `k3d-manager-vault-unseal`.
   Vault answered `400 … failed to decrypt keys from storage … message authentication failed`;
   the replay returned 42.
2. `_vault_bootstrap_ha` treated 42 as "reset": `_vault_reinit_from_reset` ran
   `_vault_purge_unseal_cache`, which cleared the Keychain cache **and deleted the
   `secrets/vault-unseal` and `secrets/vault-root` Secrets**.
3. `_vault_reset_data_path` resolved a host path that does not exist on the Mac (the k3d data lives
   inside the node container), so it hit `[[ ! -d "$host_path" ]] && return 0` and reported success
   without moving anything.
4. `_vault_operator_init` failed ("Vault is already initialized"), so the run ended with
   `ERROR: [vault] operator init did not produce artifacts`.

The Raft data survived only because step 3 found nothing. The Vault was unsealed afterwards with the
separate DR copy (`./scripts/k3d-manager hub_data_unseal_dr`, Keychain `k3dm-vault-unseal-dr`, which
the purge does not touch). `vault-root` is still gone, which arms the second destructive branch: the
next `deploy_vault` on this now-unsealed Vault hits "root token secret missing; resetting data
directory and re-initializing".

## Root cause

`_vault_bootstrap_ha` reads every way it cannot get in (rejected shards: rc 42, missing shards:
rc 43, missing `vault-root` on an unsealed Vault) as permission to destroy and re-initialise an
initialised Vault. A wrong or missing *cache* says nothing about whether the *data* is disposable.
`_vault_reinit_from_reset` also purges the credentials before it knows the reset can happen, and
`_vault_reset_data_path` reports success when it moved nothing.

## Fix

All in `scripts/plugins/vault.sh`.

### F1. An initialised Vault is never reset without an explicit opt-in

In `_vault_bootstrap_ha`, when `init_state` is `true`:

- Sealed and `replay_rc` is 42 or 43: unless `K3DM_VAULT_ALLOW_REINIT=1`, do **not** call
  `_vault_reinit_from_reset` or `_vault_purge_unseal_cache`. Print with `_warn` (to stderr) a message
  that says the Vault is initialised and sealed, that the cached shards were rejected (42) or missing
  (43), that nothing was changed, and that the recovery is `./scripts/k3d-manager hub_data_unseal_dr`
  (DR shard copy) or unsealing by hand; then `return 1`.
- Unsealed and `vault-root` missing: unless `K3DM_VAULT_ALLOW_REINIT=1`, do **not** reset. `_warn`
  that the root token Secret is missing, nothing was changed, and a new root token can be made with
  `vault operator generate-root`; then `return 1`.
- With `K3DM_VAULT_ALLOW_REINIT=1`, both branches keep today's behaviour (call
  `_vault_reinit_from_reset`). Only the exact value `1` opts in.

### F2. Nothing is purged until the data reset has succeeded

In `_vault_reinit_from_reset`, call `_vault_reset_data_path` first; call `_vault_purge_unseal_cache`
only after it returns 0. If the reset fails, warn and `return 1` with the cache and both Secrets
untouched.

### F3. A reset that moved nothing is a failure

In `_vault_reset_data_path`, when the resolved `host_path` is not a directory on this host, `_warn`
that the data path is not reachable from this host and `return 1` (today: `return 0`).

### F4. Docs

`docs/howto/vault.md`: replace "Re-unseal after restart … idempotent — safe to re-run" with the safe
order: `./scripts/k3d-manager hub_data_unseal_dr` to unseal a sealed, initialised Vault; that
`deploy_vault` now refuses to reset an initialised Vault; and that `K3DM_VAULT_ALLOW_REINIT=1`
destroys the Vault's data and is for a deliberate rebuild only.

## Tests

New file `scripts/tests/plugins/vault_bootstrap_no_destructive_reinit.bats`, in the stub style of
`scripts/tests/plugins/vault.bats` (stub `_kubectl`, `_vault_exec`, `_vault_replay_cached_unseal`,
`_vault_cache_unseal_from_secret`, `_vault_login`, `_is_vault_deployed`; record calls to
`_vault_reinit_from_reset`, `_vault_purge_unseal_cache`, `_vault_reset_data_path` in a log):

1. Initialised + sealed, replay returns 42: `_vault_bootstrap_ha` exits non-zero; no reinit, purge or
   reset call; stderr names `hub_data_unseal_dr`.
2. Same with replay 43.
3. Initialised + unsealed, `get secret vault-root` fails: exits non-zero; no reinit, purge or reset
   call; stderr names `generate-root`.
4. Replay 42 with `K3DM_VAULT_ALLOW_REINIT=1`: `_vault_reinit_from_reset` is called.
5. Replay 42 with `K3DM_VAULT_ALLOW_REINIT=true` (not `1`): no reinit.
6. `_vault_reinit_from_reset` with `_vault_reset_data_path` failing: returns non-zero and
   `_vault_purge_unseal_cache` is never called (real `_vault_reinit_from_reset`, stubbed callees).
7. `_vault_reset_data_path` with `_vault_resolve_data_path` printing a path that does not exist:
   returns non-zero and runs no `mv`/`mkdir` through `_run_command`.
8. Initialised + sealed, replay returns 0: returns 0 and calls `_vault_login` (unchanged).

Existing suites must stay green unchanged: `scripts/tests/plugins/vault.bats`,
`scripts/tests/plugins/vault_dr_shards.bats`, `scripts/tests/bin/dr_drill.bats`.

## Files

- `scripts/plugins/vault.sh`
- `scripts/tests/plugins/vault_bootstrap_no_destructive_reinit.bats` (new)
- `docs/howto/vault.md`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: deploy_vault on an initialised, sealed Vault whose cached shards are rejected or missing exits non-zero and names the DR unseal recovery.
  - id: M2
    text: deploy_vault on an initialised, unsealed Vault with no vault-root Secret exits non-zero and names generate-root.
  - id: M3
    text: K3DM_VAULT_ALLOW_REINIT=1 (exactly) still allows the reset-and-reinitialise path.
  - id: M4
    text: A successful cached unseal behaves as before.
  - id: M5
    text: docs/howto/vault.md gives the non-destructive re-unseal path and warns that the opt-in destroys data.
must_not:
  - id: N1
    text: Without the opt-in, a rejected or missing unseal cache must not purge the Keychain cache, delete vault-unseal or vault-root, or attempt a data reset.
  - id: N2
    text: Without the opt-in, a missing vault-root on an unsealed Vault must not trigger a reset.
  - id: N3
    text: The reinit path must not purge credentials when the data reset fails.
  - id: N4
    text: A data reset whose path is not a directory on this host must not report success.
  - id: N5
    text: Any opt-in value other than 1 must not enable the reset.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, N1, N2, N3, N4, N5]
    text: bats scripts/tests/plugins/vault_bootstrap_no_destructive_reinit.bats green; tests 1, 2, 3, 6 and 7 red on a temp copy of the pre-fix vault.sh; vault.bats, vault_dr_shards.bats and dr_drill.bats green unchanged; shellcheck clean on vault.sh.
  - id: E2
    kind: offline
    proves: [M5]
    text: docs/howto/vault.md diff shows the hub_data_unseal_dr path and the K3DM_VAULT_ALLOW_REINIT warning; make check-doc-links passes.
  - id: E3
    kind: live
    proves: [M2, N2]
    text: Claude or the operator runs deploy_vault against the hub while vault-root is still missing; it exits non-zero with the generate-root message, and vault status still shows Initialized true, Sealed false, the same Raft data (KV paths readable by ESO).
interface:
  - ./scripts/k3d-manager deploy_vault --confirm
  - _vault_bootstrap_ha <ns> <release> (sourced from scripts/plugins/vault.sh)
  - _vault_reinit_from_reset <ns> <release>
  - _vault_reset_data_path <ns> <release>
  - env K3DM_VAULT_ALLOW_REINIT
```

## Definition of Done

- [ ] F1–F4 and a CHANGELOG `[Unreleased]` `### Fixed` entry; only the Files above change.
- [ ] `bats scripts/tests/plugins/vault_bootstrap_no_destructive_reinit.bats scripts/tests/plugins/vault.bats scripts/tests/plugins/vault_dr_shards.bats scripts/tests/bin/dr_drill.bats` green; paste the summary.
- [ ] Tests 1, 2, 3, 6 and 7 shown red on a temp copy of the pre-fix `vault.sh`.
- [ ] `shellcheck scripts/plugins/vault.sh` adds no new warning.
- [ ] Commit: `fix(vault): never reset an initialised Vault because its unseal cache was rejected`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT touch a live cluster, the Keychain, or any real Secret; tests use stubs only.
- Do NOT change or remove any existing test or assertion.
- Do NOT change `_vault_replay_cached_unseal`, `_vault_purge_unseal_cache`, `hub_data_unseal_dr` or `bin/dr-drill`.
- Do NOT modify `scripts/lib/foundation/` or files outside the Files list.
