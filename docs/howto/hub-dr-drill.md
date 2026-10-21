# How-To: Weekly hub disaster-recovery drill

The attended drill restores the encrypted Vault, Keycloak and LDAP claims into
a throwaway `dr-drill` k3d hub on the M2. It does not contact the production
hub, publish from the M2, or run ArgoCD, platform-ops, image-updater, or
ApplicationSets. Every drill namespace gets a default-deny egress policy before
any workload starts, and check V0 proves egress is denied before Vault is
unsealed.

Architecture and diagrams: [`docs/architecture/hub-dr-drill.md`](../architecture/hub-dr-drill.md).
Plan and design decisions: `docs/plans/v1.43.0-hub-dr-drill.md`.

## One-time setup

Run every step in Terminal.app, not over a non-interactive SSH session: Keychain
writes from a session without a GUI fail or store nothing.

### 1. Data repository and SSH alias

The private repository `wilddog64/k3dm-hub-data` has a `snapshots` branch
(exports, written by the M4) and a `results` branch (drill results, written by
the M4). Its deploy keys are `m4-write` (read/write, on the M4) and `m2-read`
(read-only, on the M2). On both Macs, `~/.ssh/config` maps the alias
`github-k3dm-hub-data` to `github.com` with that Mac's deploy key.

Check it on each Mac:

```bash
git ls-remote git@github-k3dm-hub-data:wilddog64/k3dm-hub-data.git
```

### 2. The `age` identity (M2 only)

The M2 holds the only online decryption key. The M4 has the public recipient
only.

```bash
age-keygen -o ~/k3dm-hub-data.age     # prints "Public key: age1..."
```

- Keychain `security -w` hex-encodes a multi-line value, and the restore would
  then fail to decrypt. Store **only** the `AGE-SECRET-KEY-1...` line. Paste it
  at the prompt, so it never appears in argv or shell history:

  ```bash
  security add-generic-password -s k3dm-hub-data-age -a identity -w
  ```

- Keep a second copy off the M2: a Bitwarden secure note named `k3d-hub-data`
  holding the `age1...` public key and the `AGE-SECRET-KEY-1...` line. In
  Terminal.app, `grep '^AGE-SECRET-KEY-1' ~/k3dm-hub-data.age | pbcopy`, paste
  it into the note, then `pbcopy </dev/null`. Once the note shows the full line,
  `rm -P ~/k3dm-hub-data.age`. Without this copy, losing the M2 makes every
  export unreadable.
- Send the `age1...` public key to Claude to commit as
  `scripts/etc/dr/age-recipient.txt`. It is not a secret.

### 3. Vault unseal shards (both Macs)

On the M4, with the hub running:

```bash
make vault-dr-shards-save
```

This copies the shards from the `vault-unseal` Secret into Keychain service
`k3dm-vault-unseal-dr`, account `secrets/vault:*`. Vault init also does this
automatically on the real hub. A drill hub (`DR_DRILL_MODE=1`) never does, so
a drill cannot overwrite the real shards.

To copy them to the M2, export on the M4 and import on the M2 at its own
Terminal. `make vault-dr-shards-export` refuses to print to a terminal, so pipe
it:

```bash
# M4
make vault-dr-shards-export > /tmp/k3dm-dr-shards && chmod 600 /tmp/k3dm-dr-shards
# move the file to the M2 by your own means (AirDrop, scp), then on the M2:
cd ~/src/gitrepo/personal/k3d-manager && make vault-dr-shards-import < /tmp/k3dm-dr-shards
rm -P /tmp/k3dm-dr-shards    # on both Macs
```

Do not automate this transfer. When the real hub's Vault is re-initialised (a
full rebuild), Vault init replaces the M4 copy and warns that older exports
need the old shards. `make hub-recover-all` sets `K3DM_DR_SHARDS_PRESERVE=1`, so
a recovery keeps the existing shards for its restore. Export only after the
restore finishes.

### 4. Freshness workflow

After review, synchronize the authoritative
`scripts/etc/dr/drill-freshness.yml` to `.github/workflows/` and
`scripts/etc/dr/drill-freshness.sh` to the root of the data repository's
**`main`** branch. The installed script is a deployment copy; keep it aligned
with the k3d-manager source when deploying an update. Scheduled workflows run
only from the default branch; the workflow checks out `results` itself. It
fails, and GitHub emails you, when no valid result exists, the newest result
reports `success: false`, or the newest successful result is older than 8 days.
The failure log distinguishes these cases and gives the next steps: run
`make dr-drill` on M2, then `make dr-drill-publish` on M4. A stale successful
result means the evidence needs refreshing; it does not mean the recovery drill
itself failed.

## Daily export

First time, on the M4, in this order, from Terminal.app:

1. Confirm the data repo key works without a prompt (GitHub answers "successfully
   authenticated"; exit code 1 is normal): `ssh -o BatchMode=yes -T git@github-k3dm-hub-data`.
2. `make hub-data-export-setup`: creates the `hub-data-export` service account, the list-only
   `hub-data-inventory` Vault policy and role, and self-tests the login.
3. `make hub-data-export`: one manual run, which proves the new login, the upload check and the
   prune end to end.
4. `make hub-data-prune DRY_RUN=1`: read the `keep:` and `prune:` lines.
5. `make hub-data-export-schedule`: installs the 03:30 launchd job. A slot missed while the Mac
   sleeps runs on wake. `make hub-data-export-unschedule` removes it.
6. Apply the alerts once, and again whenever `prometheusrule.yaml` changes:
   `kubectl --context k3d-k3d-cluster apply -f scripts/etc/argocd/platform-ops/prometheusrule.yaml`.
   ArgoCD does not sync this file (`hub-platform-ops` includes only the app-cluster
   ExternalSecret); without this step the `HubDataExport*` and `DRDrill*` alerts never load.
7. Prove the scheduled path, not just the manual one:
   `launchctl kickstart gui/$(id -u)/com.k3d-manager.hub-data-export`, then read the log. launchd
   starts the job in `/`, so a path that only works from the repo fails here first.

The job writes `~/Library/Logs/k3dm-hub-data-export.log` and publishes the
`HubDataExportFailed`, `HubDataExportStale`, and `HubDataExportNeverRan`
alerts. Retention keeps the last five days, the newest export, and the newest
successful drill export. Preview cleanup with `make hub-data-prune DRY_RUN=1`.
The weekly export step is optional when the newest export is less than 26 hours
old. If list-only Vault login fails, rerun `make hub-data-export-setup`.

## Weekly run (about 30 minutes, attended)

1. **M4:** `make hub-data-export`. This writes an age-encrypted export of the
   three claims, `pv-pvc.yaml`, `inventory.json` and `SHA256SUMS` to the
   `snapshots` branch.
2. **M2:** `make dr-drill`, in Terminal.app. The phases log as
   `[dr-drill] Phase N/6`:
   1. preflight: refuses on the M4, with a leftover `dr-drill` cluster, below
      10 GB free Docker disk, or when the newest export is older than 26 h;
   2. build the drill hub with its own kubeconfig `~/.k3dm/dr-drill/kubeconfig`;
   3. restore each claim onto its recorded logical node;
   4. verify V0–V7;
   5. write the result;
   6. tear down. `DR_DRILL_KEEP=1` keeps the cluster and prints the delete
      command and keeps `~/.k3dm/dr-drill/kubeconfig`; use it with
      `kubectl --kubeconfig ~/.k3dm/dr-drill/kubeconfig --context k3d-dr-drill`.
3. **M4:** `make dr-drill-publish`. This copies the newest M2 result over
   `ssh m2jump`, commits it as `results/<run_timestamp>.json` on the `results`
   branch, and pushes the metrics to the hub Pushgateway (`localhost:19094`, job
   `k3dm-dr-drill`). The M2 never writes to the data repository or pushes
   metrics.

## Reading the result

`~/.k3dm/dr-drill/<run_timestamp>.json` on the M2:

| Key | Meaning |
|---|---|
| `run_timestamp` | When the drill reported (UTC). Freshness and `DRDrillStale` key on it. |
| `export` | The export the drill restored. |
| `success` | `true` only when every check V0–V7 passed. |
| `failed` | The first failure that stopped the drill: `phase2` (hub build), `phase3` (restore), `unseal`, or `V0`. |
| `rto_seconds` | Phases 2–4, build to verified. This is the **data-services** RTO: Vault, Keycloak's database and LDAP. ArgoCD, monitoring and the M4 host services are not built or timed; see `docs/plans/v1.47.0-hub-e2e-promotion-gate.md`. |
| `rpo_seconds` | Export age when the drill ran. |
| `checks` | V0–V7, each `true` or `false`. |

| Check | Proves |
|---|---|
| V0 | A fresh pod in each drill namespace cannot reach `https://github.com` (curl exit 6, 7 or 28). Runs before the unseal. |
| V1 | Vault unsealed with the Keychain shards. |
| V2 | Every Vault KV path in the export's inventory exists, using a short-lived generate-root token that is revoked afterwards. |
| V3 | The Keycloak realm user count matches the inventory. |
| V4 | The LDAP entry count matches the inventory. |
| V5 | `vault-0`, the postgres-keycloak pod and `openldap-0` are Ready on their recorded nodes. |
| V6 | RTO ≤ `DR_DRILL_RTO_BUDGET_S` (default 1800). |
| V7 | The export was ≤ 26 h old. |

The result holds counts and path names only. The drill never prints Secret
values, Vault values, shards or the age identity.

### Credential policy and clean-room check

Each drill puts the `security` shim first on `PATH`. It records only the operation, service and
account in the run directory and reports any pair outside `scripts/etc/dr/credential-allowlist.tsv`
as `credentials_unexpected`; values passed with `-w` or on `security -i` stdin are never recorded.
The default policy is `enforce` (since v1.43.1, after an audit drill came back clean): an
unexpected Keychain call exits 44 before it reaches `security`. `DR_DRILL_CREDENTIAL_POLICY=audit`
records the call and lets it through, for settling a new allowlist entry. V9 is false when any
unexpected pair is observed.

The allowlist is scoped. Its first column names who may make the call: `drill` (`bin/dr-drill`),
`restore` (`hub_data_recover`, any target), `restore-hub` (only against the real hub: the
unseal-key cache) and `restore-drill` (a rehearsal: the Keychain age identity). An account of
`${context}` matches only the target context, so a rehearsal on `k3d-dr-drill` cannot write the
hub's `k3dm-vault-root-token` entry, and neither a drill nor a rehearsal may touch
`k3d-manager-vault-unseal`. `hub_data_recover` writes `credentials_read` and
`credentials_unexpected` to its `report.json` too, across every `RESUME`.
The drill's Vault caches its unseal keys under `k3dm-vault-unseal-drill`, which
is cleared at teardown, never under the host's `k3d-manager-vault-unseal`; once
enforced, the guard refuses the host service name in the drill scope.

The restore and teardown guards also require the exact drill kubeconfig/context, the local
`dr-drill` serverlb port, and literal `dr-drill` teardown target. A refusal says
`[dr-drill] refusing: target is not the drill cluster (<reason>)` and stops before destructive work.
Review `credentials_unexpected` in the result JSON after an audit run before enabling enforce mode.

Alerts: `DRDrillFailed` (latest drill failed) and `DRDrillStale` (no drill
reported for 8 days) route to `platform-warning` email, never SMS.

## Quarterly checks

- **Bitwarden key:** decrypt one file of the newest export with the identity
  from the Bitwarden note, not the M2 Keychain copy. Copy the note's
  `AGE-SECRET-KEY-1...` line, run
  `age -d -i <(pbpaste) <file>.tar.age | tar -tf - | head`, then
  `pbcopy </dev/null`.
- **Real-hub drill:** run `make hub-recover` on the M4, then restore the data
  into the real hub (below). This is the only test of the tunnel,
  port-forwards, launchd agents and cluster registrations.

## Restoring the hub

Run these attended commands in Terminal.app on the M4. The full flow rebuilds
the hub and restores its data; the data-only flow leaves the running hub in
place. Approval is typed at the prompt and the identity is held only in memory.

```bash
make hub-recover-all       # approve, delete and rebuild the hub, credentials, then data
make hub-data-recover      # data only; hub is still running
```

The restore validates the pinned local k3d target and encrypted export, pauses
ArgoCD before replacing claims, restores and unseals Vault, re-points Kubernetes
auth, force-syncs ExternalSecrets, waits for Keycloak and restarts Keycloak,
Grafana and `argocd-server`, verifies Vault metadata and
identity digests, and writes an auditable report under
`~/.k3dm/hub-recover/<run_id>/`. A failed run can resume with `RESUME=<run_id>`;
an unfinished destructive step requires its explicit `REDO_STEP`.

`make hub-recover-all` is approval-first: it clones and validates one snapshots
export, prints live/export counts when the hub is present, and asks for that export timestamp before it
deletes and rebuilds the hub. Just before teardown it re-checks interactive Keychain access; if the
Keychain is locked, it refuses with nothing deleted. Unlock it with `security unlock-keychain` and rerun
`make hub-recover-all`. It also works when the hub is already gone and clears the
exact k3d container, network and images-volume leftovers after the snapshot guard approves teardown.
Data changed after the selected export is lost. `RESUME` reuses the recorded export; `REDO_STEP=4` or
`REDO_STEP=6` is required after an interrupted destructive step. The report
contains the selected export, checkpoint steps and return codes, every V1/V2/V3/V4/V5/V8
check, ArgoCD resume status, whether the unseal keys were cached in the Keychain
(`unseal_keys_cache`: `cached`, or `skipped` for a drill target), and RTO. The recovery RTO
runs from the typed approval to the verified report, across every `RESUME`, so time spent
fixing a failed step counts. Inventory format 2 records Vault metadata
versions and identity digests without secret values. V8 confirms that
ExternalSecrets are no longer in `SecretSyncedError`.

After the report, run `make hub-data-export-setup && make hub-data-export` to recreate
the export ServiceAccount and record a fresh export.

### M2 rehearsal

Keep the drill cluster and rehearse the data path before a real hub window:

```bash
DR_DRILL_KEEP=1 script -q ~/.k3dm/dr-drill/run.log make dr-drill   # not | tee: the drill needs a TTY
KUBECONFIG=~/.k3dm/dr-drill/kubeconfig K3DM_HUB_DATA_CONTEXT=k3d-dr-drill \
  K3DM_HUB_DATA_CLUSTER=dr-drill K3DM_HUB_DATA_RECOVER_ALLOW_DRILL=1 \
  K3DM_HUB_DATA_AGE_IDENTITY_FROM_KEYCHAIN=1 make hub-data-recover
```

Type the export timestamp at the approval prompt. `K3DM_HUB_DATA_AGE_IDENTITY_FROM_KEYCHAIN=1`
loads the age identity from the M2 Keychain instead of the prompt (useful when the pane is
viewed over ssh, where the M2's clipboard is not yours). It is refused without
`K3DM_HUB_DATA_RECOVER_ALLOW_DRILL=1`: a real recovery types the key, from the Bitwarden note.

Against a drill target the rehearsal skips what the drill cluster does not have: both ArgoCD
Applications (step 3), the Keychain unseal-key cache, so the M2's own `k3d-cluster` keys are
kept (step 6), and the Keycloak and ESO refresh (step 7). It still restores, unseals, re-points
Vault and runs V1–V5 and V8. V8 is vacuous there, because the drill cluster has no
ExternalSecrets; only a real hub recovery tests it. Step 6 does write a Keychain entry
`k3dm-vault-root-token` for account `k3d-dr-drill`, separate from the hub's.

First pass on 2026-10-11 (run `20261011T184927Z`, export `20261011T175204Z`): all nine steps
rc 0 and every check true after three fixes found by the rehearsal itself: a missing ArgoCD
Application killed step 3, step 7 restarted a Keycloak the drill does not run, and V5 could
not find `pv-pvc.yaml` outside the drill.

## Measured RTO and RPO

Add a row after each notable drill. RTO here is the data-services RTO.

| Date | RTO | RPO | Notes |
|---|---|---|---|
| 2026-10-10 | 499 s (8 min 19 s) | 459 s (7 min 39 s) | First passing live drill (run `20261010T182508Z`, export `20261010T180910Z`), V0–V7 all true. V2 checked 15 Vault paths; the export held 6 Keycloak users and 12 LDAP entries. Kept with `DR_DRILL_KEEP=1`. RPO is small because the export was taken just before the drill. |
