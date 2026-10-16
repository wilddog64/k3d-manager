# Bug: `hub-recover-all` overwrites the Vault DR shards that its own restore needs

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.2`
**Status:** VERIFIED — Claude offline: tests green, new tests red on the old code, mutations red. Awaiting live proof. Was: IMPLEMENTED — landed `861abb7b` (Codex `2f0a7896`, option B); Claude verified shellcheck clean, vault_dr_shards + hub_data 117/117, own mutation red. Pending the 2026-10-29 live drill.
**Priority:** P1 — on a single Mac the recovery cannot unseal the restored Vault; it works only if the M2 still holds the old shards and the operator copies them back by hand
**Approval:** explicit 2026-10-15 "you can dispatch four recovery fixes to codex" (operator)
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

## Fix (option B — chosen 2026-10-15; option A deferred)

Only one rule matters: during a recovery, nothing may replace the DR shards before the restore has
unsealed the old Vault. Option B enforces it with an environment flag. Option A (snapshot the shards
into the run before teardown) and option C (carry shards in the export) are deferred.

### F1 — `scripts/plugins/vault.sh`, `vault_dr_shards_save`

Old:

```bash
   if (( differs == 1 )); then
      _warn "[vault] replacing older DR shards; older exports need the old shards — run make hub-data-export now"
   fi
   _vault_dr_store_shards "$cluster" "${shards[@]}"
```

New:

```bash
   if (( differs == 1 )); then
      if [[ "${K3DM_DR_SHARDS_PRESERVE:-0}" == 1 ]]; then
         _warn "[vault] hub recovery in progress — keeping the existing DR shards for the restore; do not export until the restore finishes"
         return 0
      fi
      _warn "[vault] replacing older DR shards; older exports need the old shards — run make hub-data-export now"
   fi
   _vault_dr_store_shards "$cluster" "${shards[@]}"
```

When no shards are stored yet (`old_count` empty), `differs` stays 0 and the new shards are saved
as before. The flag only blocks replacing existing, different shards.

### F2 — `Makefile`, `hub-recover-all`

Old:

```make
	$(MAKE) --no-print-directory hub-recover; \
```

New:

```make
	K3DM_DR_SHARDS_PRESERVE=1 $(MAKE) --no-print-directory hub-recover; \
```

Only `hub-recover-all` sets the flag. A plain `make hub-recover` or `make up` is unchanged.

### F3 — tests, `scripts/tests/plugins/vault_dr_shards.bats`

Add, reusing the file's `setup()` stubs (`FAKE_SECRET`, `STORE_LOG`):

1. `vault DR shards: K3DM_DR_SHARDS_PRESERVE keeps existing different shards`. Pre-seed
   `FAKE_SECRET` with `secrets/vault:count`=`2` and two shards that differ from the
   `_vault_collect_unseal_shards_from_secret` stub. Run `vault_dr_shards_save` with
   `K3DM_DR_SHARDS_PRESERVE=1`. Assert `status` 0, `STORE_LOG` empty, the stored values unchanged,
   and stderr contains `keeping the existing DR shards`.
2. `vault DR shards: without the flag, different shards are replaced` (the same pre-seed, flag
   unset). Assert `STORE_LOG` has writes and stderr contains `replacing older DR shards`.
3. `vault DR shards: K3DM_DR_SHARDS_PRESERVE still saves when none are stored`. Assert writes happen.
4. A Makefile test, in the suite that already covers `hub-recover-all` (or a new
   `scripts/tests/lib/makefile_hub_recover.bats`). Extract the `hub-recover-all` recipe with
   `awk` from the Makefile text, and assert that the line invoking `hub-recover` carries
   `K3DM_DR_SHARDS_PRESERVE=1`. **Never run `make -n` on this target.** It executes `$(MAKE)` lines.

Mutation check: remove the `return 0` from F1, and show test 1 red; restore it from a `cp`
snapshot and `cmp`.

### F4 — docs

In `docs/howto/hub-dr-drill.md`, section 3, after "Vault init replaces the M4 copy and warns…", add:
"`make hub-recover-all` sets `K3DM_DR_SHARDS_PRESERVE=1`, so a recovery keeps the existing shards
for its restore. Export only after the restore finishes."

## Files

- `scripts/plugins/vault.sh` (`vault_dr_shards_save`)
- `Makefile` (`hub-recover-all`)
- `scripts/tests/plugins/vault_dr_shards.bats` (+ the Makefile recipe test)
- `docs/howto/hub-dr-drill.md` (section 3, and the recovery runbook)

## Definition of Done

- [ ] F3 tests 1–4 pass; test 1 is shown red under the F1 mutation.
- [ ] `shellcheck scripts/plugins/vault.sh` has no new warnings; `vault_dr_shards.bats` and the hub_data suites are green.
- [ ] Live: the 2026-10-29 rebuild drill finishes with no shard import from the M2.
- [ ] Commit message: `fix(vault): keep existing DR shards while hub-recover-all rebuilds the hub`
