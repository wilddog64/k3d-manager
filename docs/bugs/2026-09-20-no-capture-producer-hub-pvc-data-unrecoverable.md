# Hub PVC data is unrecoverable: the restore path has no capture producer, and `cluster-down` destroys it

**Filed:** 2026-09-20
**Branch:** `k3d-manager-v1.36.0`
**Severity:** Critical — data loss already occurred today and the same command will do it again.
**Status:** PARTIAL — tar-stream capture LIVE-VERIFIED (`fbebe9df`); round 5 (drop Trivy cache, atomic verified rename) dispatched to Codex

## Question that prompted this

"Ensure we can restore our data. However, I am not sure we have backup."

Answer, measured rather than assumed: **for the seven stateful hub claims, no. There is no
backup and no way to make one with a shipped command.** Application secrets are a different
story and are covered — see the split below.

## What IS restorable (verified present)

| Layer | Evidence | Verdict |
|---|---|---|
| 14 canonical app secrets, Keychain | `security find-generic-password -s k3d-manager-app-cluster-secrets -a <key>` returns 0 for all 14 (existence probe only, no values read) | **OK** |
| Same 14, in-cluster DR copy | `secrets/vault-seed-backup` on `ubuntu-hostinger`, 14 data keys, age 61d | **OK but stale** |
| Vault root token | `secrets/vault-root` on the hub + `k3dm-vault-root-token` Keychain item | **OK** |
| Stripe test key | `k3dm-stripe-sk-test`; today's rebuild logged `Restoring payment/stripe api_key from Keychain backup`, verification REAL-OK | **OK, proven in production** |

This is why the rebuild recovered the payment secrets at all. That layer works.

## What is NOT restorable

The seven claims in `_hub_recovery_records` (`scripts/plugins/hub_recovery.sh:256-266`):

```
server-0|secrets|data-vault-0
agent-1|identity|postgres-keycloak-pvc
agent-0|identity|ldap-data-pvc
agent-0|identity|data-openldap-0
agent-0|identity|ldap-config-pvc
agent-2|trivy-system|data-trivy-server-0
agent-0|monitoring|prometheus-…-prometheus-0
```

Three independent facts make these unrecoverable.

### 1 — Nothing in the repo captures a backup

`hub_recovery.sh` exposes five public functions:

```
hub_recovery_reconcile   hub_recovery_plan   hub_recovery_validate
hub_recovery_targets     hub_recovery_restore
```

`plan`, `validate` and `restore` all take **`<captured-recovery-directory>`** as their first
argument. Grepping the whole repo for a producer of that directory returns nothing — the word
`capture` appears in `hub_recovery.sh` only inside those three usage strings. `restore` hard-fails
without it:

```bash
# _hub_recovery_source_dir
if [[ -z "$source_dir" || ! -d "$source_dir" ]]; then
  echo "Hub recovery source directory is required and must exist." >&2
```

and `_hub_recovery_validate_files` additionally demands `server-db/state.db`, `server-token` and
`pv-pvc.yaml` inside it.

**The consumer half of the feature shipped; the producer half never did.** Searching the host for
those artifacts finds none (the only `state.db` on the machine is Apple's
`~/Library/IntelligencePlatform/state.db`). The v1.33.0 restore succeeded because the capture was
performed by an ad-hoc external "M2 monitor" procedure, not by this repo.

### 2 — Every PV is `reclaimPolicy: Delete`

```
$ kubectl --context k3d-k3d-cluster get sc local-path -o jsonpath='{.reclaimPolicy}'
Delete
```

All eight live PVs inherit it. Deleting a PVC or the cluster erases the backing directory. There
is no `Retain` anywhere to fall back on.

### 3 — `cluster-down` runs the one command the restore spec forbids

`docs/plans/v1.33.0-hub-local-path-restore.md` precondition 5 states:

> Never use `k3d cluster delete`, wildcard Docker volume removal, or raw SQLite deletion in this
> procedure.

`bin/cluster-down:330` does exactly that, unconditionally:

```bash
k3d cluster delete "${_HUB_CLUSTER}"
_info "[acg-down] Local Hub cluster deleted"
```

`grep -n 'backup\|capture\|snapshot\|recovery' bin/cluster-down` → **zero matches**. There is no
pre-teardown capture, no prompt, and no `--keep-data` equivalent (only `--keep-hub`, which skips
teardown entirely). It is then followed by `docker system prune --force`.

So `make down` is a silent, unrecoverable delete of all seven claims. That is what ran today, and
it is why `cosign-public-key` is "genuinely lost": it lived in Vault's KV on `secrets/data-vault-0`
and is **not** one of the 14 canonical keys, so no Keychain or `vault-seed-backup` copy exists.

### 4 — No scheduled backup of any kind

`crontab -l` → `no crontab for cliang`. No launchd agent or daemon with `backup`/`snapshot` in its
name in either `~/Library/LaunchAgents` or `/Library/LaunchDaemons`. Nothing runs periodically.

## The gap in one line

The 14 canonical *application* secrets have three redundant copies. Everything else that is
stateful on the hub — Vault's full KV including signing material, Keycloak's Postgres, all three
OpenLDAP volumes, Prometheus history, the Trivy cache — has **zero**, and the command that
destroys them is a one-liner in a Makefile target.

## Fix — proposed scope

**1 — Write the missing producer: `hub_recovery_capture`.** It must emit exactly what the
existing consumers already validate, so the two halves meet without changing `restore`:

```
<dir>/server-db/state.db
<dir>/server-token
<dir>/pv-pvc.yaml                       # kubectl get pv,pvc -A -o yaml
<dir>/node-<logical>-storage/pvc-*_<ns>_<claim>/…
```

Read each tree out of its node container with `docker exec … tar -cpf -` — the exact inverse of
`_hub_recovery_restore_one`, which already does `tar -cpf - | docker exec -i … tar -xpf -`.
Checksum every tree and write a manifest; `_hub_recovery_validate_claims` should be extended to
verify it, so a silently truncated capture cannot pass as good.

**2 — Make `cluster-down` fail closed.** It must refuse to delete the hub unless either a fresh
capture exists or the operator passes an explicit opt-out flag naming the consequence
(`--discard-hub-data`). Default behaviour must not be silent data loss. Print the resolved capture
path and its age before proceeding.

**3 — Switch the seven mapped claims to `Retain`.** A second, cheaper safety net: released PVs
survive a PVC delete and can be re-bound. Needs a dedicated storage class, since `local-path`'s
policy is cluster-wide.

**4 — Schedule it.** A launchd agent running the capture daily, with the log surfaced in
`make status` so a stale or failing backup is visible rather than assumed. `make status` currently
reports nothing at all about backup freshness.

**5 — Extend the canonical key list, or stop relying on it.** The 14-key list is a hand-maintained
allowlist; anything written to Vault outside it is silently unprotected, which is precisely how
`cosign-public-key` was lost. Prefer a full KV enumeration at capture time over a static list.

## Immediate, separate from the fix

The **current** hub data is 80 minutes old and equally unprotected. A manual capture of the seven
claims should be taken before any further `make down`, `make refresh`, or cluster surgery. This is
an operator action on live Docker containers and needs the user's go.

`k3d-k3d-cluster-recovery-server-data` (created 2026-09-10) still exists and was deliberately
spared during the debris cleanup, but it is an orphan from the previous recovery cluster, holds
only server-node data, and has never been validated as a capture. It is **not** a backup.

## Definition of Done

- [ ] `hub_recovery_capture` exists and its output passes `hub_recovery_validate` unmodified
- [ ] Round-trip proven: capture → rebuild → restore, with a sentinel value written before and
      read after
- [ ] `cluster-down` refuses to destroy hub data without a fresh capture or an explicit opt-out
- [ ] Capture freshness reported by `make status`
- [ ] BATS coverage for the manifest/checksum validation
- [ ] `docs/howto/` procedure updated to reference the shipped command, not the ad-hoc M2 monitor
- [ ] CHANGELOG `[Unreleased] → ### Added` / `### Fixed`

## What NOT to Do

- Do NOT treat the Keychain seed backup as hub coverage. It holds 14 app secrets; it does not
  hold Vault's KV, LDAP, or Keycloak's database.
- Do NOT delete `k3d-k3d-cluster-recovery-server-data` until a validated capture exists.
- Do NOT "fix" this by removing `k3d cluster delete` from `cluster-down` without providing the
  capture first — that trades data loss for an unusable teardown.
- Do NOT run `signing_init` to recover `cosign-public-key`.

## Remaining fix (2026-10-08)

State on `k3d-manager-v1.42.0`, re-checked by Claude:

| Item | State |
|---|---|
| 1 — capture producer | **Done**, `d53ea1ba`: `hub_snapshot_capture` / `make snapshot` copies server DB, token, `pv-pvc.yaml` and all seven claims to the M2, with `SHA256SUMS` verified on the M2. |
| 2 — fail-closed teardown | **Partly done.** `make down` keeps the hub by default now; `DELETE_HUB=1` → `--delete-hub` still deletes it with no snapshot check. The `k3d` provider deletes it by implication, also unchecked. |
| 3 — Retain | **Open.** |
| 4 — schedule + freshness | Scheduling is **not** in scope: operator decision D7 in `docs/plans/v1.43.0-hub-dr-drill.md` is "nothing runs unattended". Freshness in `make status` is **open**. |
| 5 — Vault coverage | **Done** by item 1: the snapshot copies the whole `secrets/data-vault-0` volume, so every KV key is in it, not only the 14 canonical ones. |

### Fix A — `cluster-down` refuses to delete the hub without a fresh snapshot

Target files: `scripts/plugins/hub_snapshot.sh`, `bin/cluster-down`, `Makefile`.

1. In `hub_snapshot.sh` add:
   - `K3DM_SNAPSHOT_MAX_AGE_HOURS="${K3DM_SNAPSHOT_MAX_AGE_HOURS:-24}"`
   - `K3DM_SNAPSHOT_STAMP="${K3DM_SNAPSHOT_STAMP:-${HOME}/.local/share/k3d-manager/hub-snapshot-last}"`
   - `_hub_snapshot_age_hours <name>`: prints the whole-hour age of a `YYYYmmddTHHMMSSZ` name (UTC). Use `python3 -c` for the date maths so it works on macOS and Linux; return 1 for a name that does not parse.
   - `_hub_snapshot_latest_verified`: prints the newest name from `_hub_snapshot_remote_names` that does not end in `.INCOMPLETE`; prints nothing and returns 1 when none exist or the M2 is unreachable.
   - `hub_snapshot_guard_delete`: returns 0 when the latest verified snapshot is ≤ `K3DM_SNAPSHOT_MAX_AGE_HOURS` old and prints `[hub-snapshot] latest verified snapshot <name> on <host> is <N>h old`. Otherwise returns 1 with an `_err` naming the reason (M2 unreachable / none / too old with its age) and the two ways forward: `make snapshot`, or `DISCARD_HUB_DATA=1` (`--discard-hub-data`), which permanently loses the seven claims.
2. At the end of a successful `hub_snapshot_capture` (after the remote checksum passes), write the timestamp to `K3DM_SNAPSHOT_STAMP` (create the parent dir). The stamp is a convenience for `make status` only; the guard never trusts it.
3. `bin/cluster-down`:
   - accept `--discard-hub-data`; add it to the usage text.
   - When `_keep_hub` is 0 (from `--delete-hub` **or** the `k3d` provider implication), the hub cluster exists, and `--discard-hub-data` is not set: source `"${PLUGINS_DIR}/hub_snapshot.sh"` and call `hub_snapshot_guard_delete`. On failure `exit 2` **before any teardown step runs** — place the check right after the flag/confirm validation, not at the hub-delete step, so a refusal never leaves the remote cluster half torn down.
   - Under DRY_RUN, run the guard, report its verdict with `_info "DRY_RUN: ..."` and do not exit.
   - With `--discard-hub-data`, `_warn` once that the seven claims will be destroyed with no snapshot, then proceed.
4. `Makefile`: `DISCARD_HUB_DATA ?= 0`; when it is 1, append `--discard-hub-data` to the `cluster-down` call `make down` builds. Add it to the `make down` help line.

### Fix B — snapshot freshness in `make status`

Target file: `bin/cluster-status-summary`. In text mode only (not `--json`), before the `Details: make status-full` line, print one line:
- stamp present: `Hub snapshot: <name> (<N>h old)`; yellow `!` when older than 7 days, otherwise green `✓`;
- stamp absent: yellow `! Hub snapshot: none recorded — run make snapshot`.

It reads only the local stamp file (no ssh, so `make status` never waits on the M2), and it does **not** change the exit code or the error/warning counts.

### Fix C — Retain on the seven mapped claims (operator-run)

Target files: `scripts/plugins/hub_snapshot.sh`, `Makefile`.

`hub_snapshot_retain_pvs`: for each record in `_hub_recovery_records`, resolve the bound PV (`_hub_snapshot_claim_pv`) and, if its `persistentVolumeReclaimPolicy` is not `Retain`, `_kubectl patch pv <pv> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'`. Print `<ns>/<claim> <pv> <old> -> Retain` or `already Retain`. Idempotent; a missing PVC is an `_err` and a non-zero return after the loop finishes. Make target `hub-retain-pvs`. Do not change the `local-path` StorageClass.

Limit, to state in the howto: Retain protects the data from a PVC delete only. `k3d cluster delete` removes the node containers and their storage regardless — Fix A is the guard for that. A rebuilt hub gets new PVs with `Delete`, so the target is re-run after each rebuild.

### Tests (BATS, stubbed — no cluster, no ssh, no docker)

`scripts/tests/plugins/hub_snapshot.bats`:
- guard passes for a 2h-old verified snapshot; fails for 30h old, for only `.INCOMPLETE` entries, and for an unreachable M2 (stub `_hub_snapshot_ssh` return 255); the failure text names `DISCARD_HUB_DATA=1`;
- `_hub_snapshot_age_hours` returns 1 for a malformed name;
- capture writes the stamp only after the remote checksum passes (checksum failure → no stamp);
- `hub_snapshot_retain_pvs` patches a `Delete` PV, skips an `already Retain` one, and returns non-zero for a missing PVC while still processing the rest.

`scripts/tests/bin/cluster_down.bats`:
- `--delete-hub` with a failing guard exits 2 and never calls `k3d cluster delete` or any remote teardown stub;
- `--delete-hub --discard-hub-data` deletes without calling the guard;
- the `k3d` provider implication is guarded too (update the existing "deletes the local hub by implication" case to pass `--discard-hub-data` or a passing guard stub);
- the Makefile maps `DISCARD_HUB_DATA=1` to `--discard-hub-data` (extend the existing mapping case; never run `make down` or `make -n down`).

`scripts/tests/bin/cluster_status_summary.bats`: fresh stamp → `✓ Hub snapshot`; 8-day stamp → `!`; no stamp → `none recorded`; exit code unchanged in all three.

Show RED for the `--delete-hub` refusal case against the pre-fix `bin/cluster-down` on a temp copy.

### Docs

- `docs/howto/hub-snapshots.md`: the delete guard, `DISCARD_HUB_DATA=1`, the stamp and `make status` line, `make hub-retain-pvs` and its limit.
- `docs/howto/makefile.md`: `DISCARD_HUB_DATA`, `hub-retain-pvs`.
- `CHANGELOG.md` `[Unreleased]` → `### Fixed`.

## Review findings — round 1 (Claude, 2026-10-08, against `fa3340bc`)

The live safety property holds: with no fresh snapshot, `cluster-down --delete-hub` stops before
any teardown. Three defects remain.

1. **The guard exits 1 through `_err`, not 2.** `_err` in lib-foundation `system.sh` prints and
   then calls `exit 1`. So `hub_snapshot_guard_delete` never returns, and `bin/cluster-down`'s
   `exit 2` and its DRY_RUN branch can't be reached. Fix: in `hub_snapshot_guard_delete`, report
   each refusal with `_warn` (or `printf 'ERROR: ...' >&2`) and then `return 1`. Keep the message
   text, which names `make snapshot` and `DISCARD_HUB_DATA=1`.
2. **Under DRY_RUN the guard parses the dry-run preview as data.** `_hub_snapshot_ssh` calls
   `_run_command`, and the `system_overrides.sh` dry-run override prints
   `[dry-run] ssh ...` and returns 0. `_hub_snapshot_latest_verified` then takes that line as a
   snapshot name ("latest snapshot [dry-run] ssh ... has an invalid timestamp"). The guard's calls
   are read-only, so they should really run even in a preview. Fix: run the guard's reads with
   `DRY_RUN=0 K3DM_DEPLOY_DRY_RUN=0` scoped to those calls, for example a `local` override or a
   subshell inside `hub_snapshot_guard_delete`. `hub_snapshot_capture` and `hub_snapshot_prune`
   keep honoring DRY_RUN.
3. **The tests lock in defect 1, and one change is outside the spec.**
   - `acg-down refuses hub deletion without a verified snapshot` asserts `status -eq 1`, which
     passes only because `_err` exits.
   - Replace it with two tests, both stubbing `ssh` on PATH to list no verified snapshot:
     - a non-DRY_RUN run asserts `status -eq 2`, the `DISCARD_HUB_DATA=1` message, and no
       `k3d cluster delete` and no provider call;
     - a DRY_RUN run asserts `status -eq 0`, `DRY_RUN: hub snapshot guard refused`, and that
       the preview continued.
   - Add a test where a fresh snapshot (a name built from the current UTC time) lets deletion
     proceed.
   - Show RED for the `status -eq 2` test against `fa3340bc` on a temp copy.
   - Revert `_hub_snapshot_ssh`'s `--probe " "` back to the plain `_run_command -- ssh ...`. Under
     Bash 3.2 a whitespace probe still leaves `probe_args` empty, so it fixes nothing (checked with
     `/bin/bash -c 'set -u; local -a a=(); read -r -a a <<< " "; g "${a[@]}"'`, which still reports
     unbound). Under Bash 5 it isn't needed. If a test genuinely needs it, show that test failing
     without it.

## Live verification — round 3 (operator, 2026-10-08)

- `make hub-retain-pvs`: **passed.** All 8 mapped PVs went Delete → Retain. The record table has 8
  claims (it includes `monitoring/storage-loki-0`), not 7.
- `make status`: refused before printing anything, because two providers are live and
  `CLUSTER_PROVIDER` wasn't set. That's the existing multi-provider gate, not a defect. Rerun with
  `CLUSTER_PROVIDER=k3s-aws`.
- `make snapshot`: **failed.** Output:

  ```text
  Error response from daemon: No such container: k3d-k3d-cluster-k3d-k3d-cluster-agent-1
  docker command failed (1): docker cp k3d-k3d-cluster-k3d-k3d-cluster-agent-1:/var/lib/rancher/k3s/storage/pvc-..._secrets_data-vault-0/. ...
  ```

  The real containers are `k3d-k3d-cluster-{server-0,agent-0,agent-1,agent-2}`.

### Root cause

`hub_snapshot_capture` (`scripts/plugins/hub_snapshot.sh:162`) passes
`_hub_snapshot_claim_node`'s result to `_hub_snapshot_node_container`. That result is the PV's
`nodeAffinity` hostname, which on a real k3d hub is the full node name `k3d-k3d-cluster-agent-1`.
`_hub_snapshot_node_container` then prepends `k3d-k3d-cluster-` again. Line 151 passes the
logical name `server-0` and is correct.

The tests missed it because the `kubectl` stub in `hub_snapshot.bats` (line 44) returns the
logical name `agent-1`, which a real cluster never returns. So capture has never worked live
since `d53ea1ba`.

### Fix (round 3, for Codex)

1. At line 162, map the hostname to its logical node before building the container name, using
   the existing helper in `hub_recovery.sh` (already sourced):

   ```bash
   _container="$(_hub_snapshot_node_container "$(_hub_recovery_logical_node "$_node")")" || return 1
   ```

   Do not change `_hub_snapshot_node_container` or line 151. Note `|| return 1`: an unsupported
   hostname must stop capture, not run `docker cp` against an empty container name. If command
   substitution inside the argument hides the failure, split it into two assignments, each with
   `|| return 1`.
2. Change the `hub_snapshot.bats` kubectl stub (line 44) to return real hostnames,
   `k3d-k3d-cluster-agent-1` and `k3d-k3d-cluster-agent-0`. Leave the MANIFEST.tsv assertions
   (logical `agent-1`) as they are, if MANIFEST still records the logical node; if it records the
   hostname, report which and don't change it.
3. Assert the container name: the `docker` stub must record `k3d-k3d-cluster-agent-1:` in its
   `cp` args, and must never record a doubled `k3d-k3d-cluster-k3d-` prefix.
4. RED: the changed stub plus the assertion fail against `32395370` on a temp worktree.

## Live verification — round 4 (operator, 2026-10-08, after `2e8996ae`)

The container name is now correct (`k3d-k3d-cluster-agent-1`). Capture fails at the first claim:

```text
fchmodat2 raft: operation not permitted
docker command failed (1): docker cp k3d-k3d-cluster-agent-1:/var/lib/rancher/k3s/storage/pvc-..._secrets_data-vault-0/. /tmp/k3dm-hub-snapshot.34RvGY/node-server-0-storage/pvc-..._secrets_data-vault-0
```

### Root cause (Claude, read-only checks)

- In the node, Vault's `raft` directory is `drwx--S--- 100:1000`, which has the setgid bit set.
- `docker cp` to the macOS host extracts with the original modes. The operator's `TMPDIR=/tmp`, and
  `/private/tmp` is group `wheel`, so new directories inherit group `wheel`.
- macOS refuses setgid on a directory whose group the user doesn't belong to. The operator isn't
  in `wheel`, so the call fails with EPERM.
- Second, latent problem: `docker cp` to the host also drops ownership. Vault's files (uid 100,
  mode 0600) would come back owned by the operator. Even a "successful" copy would not restore
  cleanly.

### Fix (round 4, for Codex)

Capture each source as a tar stream from inside the node. The host then never applies modes or
ownership, and the archive keeps owner, mode and setgid for restore. BusyBox `tar` is at `/bin/tar`
in the k3s node image (checked live).

1. Replace `_hub_snapshot_copy`'s `docker cp` with:

   ```bash
   function _hub_snapshot_copy() {
     local _container="$1" _source="$2" _destination="$3"
     _run_command -- docker exec "$_container" tar -C "$_source" -cf - . > "$_destination"
   }
   ```

   Here `_destination` is a `.tar` file path.
2. Callers:
   - `server-db` writes `${_stage}/server-db.tar`.
   - Each claim writes `${_stage}/${_storage}/pvc-${_uid}_${_namespace}_${_claim}.tar`. Create
     only the `${_stage}/${_storage}` directory, not a per-claim directory.
   - A failed copy must still `return 1` and trigger `.INCOMPLETE`, as today.
   - `MANIFEST.tsv`'s last column stays the claim directory name, without `.tar`.
3. `SHA256SUMS` and the remote `sha256sum -c` work unchanged, since they hash every file.
4. Tests (`hub_snapshot.bats`):
   - The docker stub handles `exec <container> tar -C <path> -cf - .` by writing a real tar of a
     fixture dir to stdout, and logs the args.
   - Update the existing assertions that expect copied files to expect `.tar` archives.
   - Add a test that the archive lists the fixture's files (`tar -tf`).
   - Keep the logical-container test, now asserting `docker exec k3d-k3d-cluster-agent-1 tar`.
   - Assert no `docker cp` is called anywhere.
   - RED: the new tar assertions fail at `2e8996ae` on a temp worktree.
5. `docs/howto/hub-snapshots.md`: say each claim is stored as `<claim-dir>.tar`, which keeps owner,
   mode and setgid, and that a restore extracts it inside the node (`docker exec -i <node> tar -C
   <path> -xpf -`), not on the Mac. Restore itself remains the v1.43.0 DR drill's scope.

Out of scope: hot-copy consistency of `vault.db` while Vault runs (v1.43.0 DR drill), and
`hub_recovery.sh`.

## Live verification — round 5 (operator, 2026-10-08, after `fbebe9df`)

`make snapshot` from the operator's tmux pane, 18:42 PDT:

- **Capture works.** server-db plus all 8 claims were archived in about 2 minutes, with no setgid
  error. Staging was 4.7 GB.
- **The upload is the bottleneck.** rsync to `m2jump` ran at about 3.8 MB/s. The operator cancelled
  it (`INT`, 12m40s) at about 2.0 GB to take the two fixes below first.

Archive sizes: Prometheus 2.6 GB, Trivy 1.4 GB, server-db 465 MB, Loki 182 MB, Keycloak Postgres
68 MB, Vault 49 MB, OpenLDAP under 0.5 MB.

### Finding A — the Trivy claim is a re-downloadable cache (1.4 GB, 30% of every snapshot)

The `data-trivy-server-0` archive holds only `trivy/db/trivy.db` (1.46 GB, the public
vulnerability DB) and `trivy/fanal/fanal.db` (8 MB, scan cache). The repo has no offline or
air-gapped Trivy setting, so the server downloads a fresh DB at startup.

Scan results are not in this volume. They are VulnerabilityReport CRs in the datastore, which
`server-db.tar` already captures. Backing it up preserves nothing that a restart does not rebuild.

### Finding B (safety) — an interrupted upload is indistinguishable from a verified snapshot

`hub_snapshot_capture` rsyncs straight into the final `<ts>` directory. It only renames to
`<ts>.INCOMPLETE` when `sha256sum -c` fails. An interrupt, a kill, a dropped ssh or a laptop sleep
during the rsync leaves a bare `<ts>` directory, and `SHA256SUMS` may already be inside it.

`_hub_snapshot_latest_verified` and `hub_snapshot_list` treat every non-`.INCOMPLETE` name as
verified. So after tonight's cancel, `k3dm-snapshots/20261009T014249Z/` (partial) would satisfy
the teardown guard for 24h. `make down DELETE_HUB=1` would then destroy the hub against a broken
backup, which is exactly what the guard exists to prevent.

### Fix (round 5, for Codex)

1. **Drop Trivy from the claim set.** Delete the
   `agent-2|trivy-system|data-trivy-server-0|node-agent-2-storage` line from
   `_hub_recovery_records` in `scripts/plugins/hub_recovery.sh`. The set becomes 7 claims. Capture,
   `hub-retain-pvs` and restore all read this one list, so nothing else needs a per-claim edit.
   After a restore, Trivy gets a fresh dynamically provisioned PVC and downloads its DB.
2. **Upload to a staging name, then rename only after verification.** In `hub_snapshot_capture`:
   - rsync into `${_remote}.INCOMPLETE/`, not `${_remote}/`;
   - run `sha256sum -c SHA256SUMS` inside `${_remote}.INCOMPLETE`;
   - only on success, `mv -- '${_remote}.INCOMPLETE' '${_remote}'` over ssh, then write the stamp;
   - on verify failure, leave it as `.INCOMPLETE`. `_hub_snapshot_remote_mark_incomplete` is no
     longer needed in that path; remove it if it becomes unused;
   - check the rsync exit status: on failure, `_err` with the timestamp and return 1, leaving the
     `.INCOMPLETE` directory in place.

   A bare `<ts>` name therefore exists only after a passing `sha256sum -c`, whatever kills the
   process. `_hub_snapshot_latest_verified` and `hub_snapshot_list` stay as they are.
3. **Fix the counts in tests and docs.** `scripts/tests/plugins/hub_recovery.bats`: the
   "eight-claim" test becomes seven, and remove or rewrite the trivy-specific assertions near
   lines 125–129. `scripts/tests/plugins/hub_snapshot.bats`: drop the trivy fixture. Update
   `docs/howto/hub-snapshots.md`:
   - list the 7 claims;
   - state that the Trivy DB is deliberately excluded, and why;
   - add the `.INCOMPLETE`-until-verified rule.

### Tests (round 5)

- `_hub_recovery_records` has 7 lines, and none contains `trivy`.
- Capture with stubs: the rsync destination ends in `.INCOMPLETE/`. The remote `mv` to the bare
  name runs after `sha256sum -c` and before the stamp write.
- Failing rsync stub: return 1, no `mv` to the bare name, no stamp written.
- Failing `sha256sum -c` stub: no `mv` to the bare name, no stamp written.
- RED: the rsync-destination and failing-rsync tests fail against `fbebe9df` on a temp worktree.

### Operator action (one-off, not part of the fix)

The partial directory from tonight's cancel predates the fix and has a bare name. It must not stay
readable as verified. Rename it on the M2, rather than deleting it, so the operator can inspect
it:

```bash
ssh m2jump 'mv k3dm-snapshots/20261009T014249Z k3dm-snapshots/20261009T014249Z.INCOMPLETE'
```

