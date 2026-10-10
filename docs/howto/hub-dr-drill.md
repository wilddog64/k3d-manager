# How-To: Weekly hub disaster-recovery drill

The attended drill restores the encrypted Vault, Keycloak and LDAP claims into
a throwaway `dr-drill` k3d hub on the M2. It does not contact the production
hub, publish from the M2, or run ArgoCD, platform-ops, image-updater, or
ApplicationSets. Every drill namespace gets a default-deny egress policy before
any workload starts, and check V0 proves egress is denied before Vault is
unsealed.

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

- Copy `~/k3dm-hub-data.age` to the offline medium, then delete it from disk.
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
need the old shards. Run `make hub-data-export` straight away, then repeat this
transfer for the M2.

### 4. Freshness workflow

Copy `scripts/etc/dr/drill-freshness.yml` to `.github/workflows/` and
`scripts/etc/dr/drill-freshness.sh` to the root of the data repository's
**`main`** branch. Scheduled workflows run only from the default branch; the
workflow checks out `results` itself. It fails, and GitHub emails you, when the
newest result is older than 8 days or reports `success: false`.

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
      command.
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
| `rto_seconds` | Phases 2–4, build to verified. |
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

Alerts: `DRDrillFailed` (latest drill failed) and `DRDrillStale` (no drill
reported for 8 days) route to `platform-warning` email, never SMS.

## Quarterly checks

- **Offline key:** decrypt one file of the newest export with the **offline**
  identity, not the M2 Keychain copy:
  `age -d -i <offline identity> <file>.tar.age | tar -tf - | head`.
- **Real-hub drill:** run `make hub-recover` on the M4, then restore the data
  into the real hub (below). This is the only test of the tunnel,
  port-forwards, launchd agents and cluster registrations.

## Promoting a drill restore to a real restore

The drill proves an export restores. To restore the real hub from it:

The restore streams into the hub's node containers with `docker exec`, so it
must run on the M4, the hub's own Docker host. The M4 normally holds no age
identity, so this is the one time the offline copy goes on the M4, temporarily.

1. Rebuild the hub on the M4 (`make hub-recover`), so the claims exist.
2. On the M4, store the offline identity's `AGE-SECRET-KEY-1...` line at the
   prompt: `security add-generic-password -s k3dm-hub-data-age -a identity -w`.
3. Run the restore against the real hub. It scales Vault, postgres-keycloak and
   OpenLDAP to zero, recreates their claims, and stops at the first claim whose
   PV is not on its recorded logical node:

   ```bash
   DR_DRILL_CONTEXT=k3d-k3d-cluster DR_DRILL_CLUSTER=k3d-cluster \
     ./scripts/k3d-manager hub_data_restore
   ```

4. Remove the identity from the M4 straight away:
   `security delete-generic-password -s k3dm-hub-data-age -a identity`.
5. Unseal Vault with the Keychain shards and confirm V1–V5 by hand.

## Measured RTO and RPO

Record these after the first live drill.

| Date | RTO | RPO | Notes |
|---|---|---|---|
| | | | |
