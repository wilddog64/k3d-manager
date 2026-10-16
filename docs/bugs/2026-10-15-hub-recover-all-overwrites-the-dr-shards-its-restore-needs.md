# Bug: `hub-recover-all` overwrites the Vault DR shards that its own restore needs

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.2`
**Status:** OPEN
**Priority:** P1 — on a single Mac the recovery cannot unseal the restored Vault; it works only if the M2 still holds the old shards and the operator copies them back by hand
**Approval:** pending — filed by Claude during the operator's live run `20261016T012103Z`; the fix needs operator approval
**Severity:** critical — the M4 copy of the only key that opens the exported Vault data is destroyed by the recovery itself

## Symptom

Live run `20261016T012103Z` (2026-10-15). During `hub-up`, Vault init printed:

```text
WARN: [vault] replacing older DR shards; older exports need the old shards — run make hub-data-export now
```

Later, the `RESUME` restore failed at Step 5/9:

```text
[hub-recover] vault operator unseal failed for shard 1 of 1
[hub-recover]   * unable to retrieve stored keys: invalid key: failed to decrypt keys from storage: error decrypting seal wrapped value
[hub-recover]   error decrypting using seal shamir: cipher: message authentication failed
```

## Root cause

`hub-recover-all` runs teardown, then `make hub-recover` (which runs `hub-up`), then
`RESUME=<run_id> hub_data_recover`.

1. `hub-up` Step 3 deploys and initialises a new Vault. Vault init calls `vault_dr_shards_save`
   (`scripts/plugins/vault.sh:390`). That function sees the new shards differ from the stored ones,
   warns, and **replaces** Keychain service `k3dm-vault-unseal-dr` on the M4 with the new Vault's
   shards.
2. `hub_data_recover` Step 4 restores the export's Vault PVC, which holds the **old** Vault's
   storage, sealed with the old shards.
3. Step 5 `hub_data_unseal_dr` (`scripts/plugins/hub_data.sh:576`) reads `k3dm-vault-unseal-dr`,
   now holding the new shards, and cannot decrypt the old barrier.

The warning's advice to run `make hub-data-export now` is also wrong at that point: the hub is
empty and the restore has not run, so an export would capture an empty hub.

## Workaround (used on run `20261016T012103Z`)

The M2's Keychain copy changes only on a manual import, so it still held the old shards:

```bash
# M2, Terminal.app
make vault-dr-shards-export > /tmp/k3dm-dr-shards && chmod 600 /tmp/k3dm-dr-shards
# copy to the M4, then on the M4:
make vault-dr-shards-import < /tmp/k3dm-dr-shards
rm -P /tmp/k3dm-dr-shards   # both Macs
RESUME=<run_id> ./scripts/k3d-manager hub_data_recover
```

## Fix (to design before dispatch)

Only one rule matters: during a recovery, nothing may replace the DR shards before the restore has
unsealed the old Vault. Options:

- **A. Snapshot before teardown.** `hub_data_recover_preflight` copies the current DR shards into
  the run (in memory, or a run-scoped Keychain account such as `secrets/vault@<run_id>`), and Step
  5 unseals with that copy. Simple, and it also covers a hub that was never exported.
- **B. Suppress the save during recovery.** `hub-up` under `hub-recover` sets a flag so
  `vault_dr_shards_save` refuses to replace existing shards. After a successful Step 5 the old
  shards are correct again, and no re-save is needed.
- **C. Carry the shards in the export,** age-encrypted like the PVCs. Larger change, and it puts
  the unseal key next to the data it unseals, which weakens the two-factor split. Not recommended.

Recommendation: A plus B. B stops the damage, and A makes the restore independent of Keychain
timing. Also make the warning conditional: inside a recovery, say "restore pending — do not
export yet".

## Files

- `scripts/plugins/vault.sh` (`vault_dr_shards_save`)
- `scripts/plugins/hub_data.sh` (`hub_data_recover_preflight`, `hub_data_unseal_dr`)
- `Makefile` (`hub-recover-all`, if a flag is passed)
- BATS for both functions
- `docs/howto/hub-dr-drill.md` (section 3, and the recovery runbook)

## Definition of Done

- [ ] A test proves that `hub-recover-all` with a stubbed Vault init leaves `k3dm-vault-unseal-dr`
      unchanged until Step 5 finishes. Check the test fails against the pre-fix source.
- [ ] A test proves Step 5 unseals with the shards captured before the teardown.
- [ ] Live: the 2026-10-29 rebuild drill finishes with no shard import from the M2.
- [ ] Commit message: `fix(hub-data): keep the pre-teardown DR shards through hub-recover-all`
