# Hub PVC data is unrecoverable: the restore path has no capture producer, and `cluster-down` destroys it

**Filed:** 2026-09-20
**Branch:** `k3d-manager-v1.36.0`
**Severity:** Critical — data loss already occurred today and the same command will do it again.

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
