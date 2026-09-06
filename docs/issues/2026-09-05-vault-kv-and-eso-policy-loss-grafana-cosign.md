# Post-incident: Vault KV data + ESO policy loss (Grafana outage, cosign sync failure)

**Date:** 2026-09-05
**Surfaced by:** Hermes (Phase-1 v1.29.0, read-only observe/correlate/report — advisory only; remediation was direct ops via kubectl/Vault).
**Status:** CLOSED — both fixes verified, committed, and pushed.

## Finding

Two independent symptoms on the hub, correlated to a single class of root cause:

1. **Grafana outage (real, ~27h):** `kube-prometheus-stack-grafana` pod in
   `CreateContainerConfigError` — the ExternalSecret backing its admin credentials
   could not sync because the Vault KV path `secret/observability/grafana` did not
   exist.
2. **cosign public key not syncing (Audit-mode, no outage):** the
   `cosign-public-key` ExternalSecret in `platform-ops` reported
   `SecretSyncedError` / `could not get secret data from provider`. The Vault KV
   path `secret/cosign/signing` did not exist.

## Root cause

Both KV trees — `secret/observability/grafana` and `secret/cosign/signing` — were
missing from an otherwise-healthy Vault. A cluster-wide ExternalSecret sweep was
clean everywhere else (7 total; the only other unsynced one,
`platform-ops/app-cluster-kubeconfig`, is a separate, expected open seam — the
app-cluster Vault-auth portability item — with no app-cluster registered).

The cosign case had a **second, independent failure layer**: even after the KV data
was restored, the ExternalSecret still returned `403 permission denied on GET
secret/data/cosign/signing`. The `cosign-verify` Vault policy **and** its grant on
the shared `eso-ldap-directory` Kubernetes-auth role had also been lost. Grafana did
**not** hit this second layer only because the existing `eso-ldap-directory` policy
already granted `observability/*`.

### Confirmed mechanism (2026-09-05 forensics)

The initial "scoped, surgical loss" reading was **wrong** — it *was* a general wipe.
Forensics on the live hub:

- **The entire k3d cluster was rebuilt on 2026-09-04 (~10:28).** All four nodes and
  *every* PVC are the same age with **new PVC UIDs** — a full `k3d` teardown+recreate,
  not a restart (a restart preserves PVC age/UID).
- **Vault uses raft storage on `data-vault-0` (`local-path`).** `local-path` volumes
  are node-local and destroyed on cluster teardown, so **Vault's raft store started
  empty and Vault was re-initialized from scratch** (fresh cluster ID, "Active Since
  2026-09-04T17:29:39Z"). Every KV entry is `version 1, oldest_version 0` — zero
  history, consistent with a brand-new store. No audit device is enabled, so there is
  no per-operation trail, but the metadata is conclusive.
- **The loss was total; only the *reseeders* differ.** KV `created_time` proves it:
  `ldap/openldap-admin` was recreated at `2026-09-04T17:30:02Z` (~23s after Vault went
  active — automation, not a human), and `ldap/admin` / `keycloak/*` at
  `2026-09-04T20:17Z` when the identity stack deployed. `observability/grafana`
  (`2026-09-05T23:28Z`) and `cosign/signing` (`2026-09-05T23:42Z`) carry the manual
  restore timestamps — they had **no** automatic bring-up seeder:
  - **grafana:** `_observability_apply_grafana_rotator` (`observability.sh`) creates
    the `grafana-rotation` *policy* + writer *role* (`_vault_configure_secret_writer_role`,
    `vault.sh`) but **never writes the KV data**. So the policy reappeared while the
    secret did not, and the rotator CronJob cannot bootstrap an empty path.
  - **cosign:** the KV data, the `cosign-verify` policy, and the ESO role grant are
    seeded **only** by the manual, opt-in `signing_init` / `deploy_image_signing`
    (`signing.sh`) — never by standard bring-up. All three share that one seeder,
    which is why all three were absent together; re-running it would *regenerate* the
    key (destructive), so the correct fix was the manual restore, not `signing_init`.

The 2026-09-04 rebuild itself is a cluster-lifecycle event external to Vault (a
`k3d`/`make` rebuild or an OrbStack/laptop reset); its exact trigger is not recorded
in-cluster.

## Remediation

- **Grafana:** seeded `secret/observability/grafana` with
  `{username: admin, password: <fresh>}` matching the
  `grafana-credential-rotator` `restore()` schema → ExternalSecret `SecretSynced`,
  secret created, pod recovered `0/3 → 3/3 Running`.
- **cosign (data):** **restored the ORIGINAL signing key** from its macOS Keychain
  backup (service `k3d-manager-signing`) into `secret/cosign/signing`. This was a
  restore, not a regenerate — `signing_init` / `_signing_seed_vault_key` were
  **never** called, because that path regenerates the keypair and clobbers the
  Keychain backup, destroying the original key. `cosign.pub` was derived on the host
  from the restored key + password and written alongside `cosign.key` /
  `cosign.password`.
- **cosign (policy):** wrote the `cosign-verify` policy
  (`path "secret/data/cosign/signing" { capabilities = ["read"] }`) and appended it
  to the `eso-ldap-directory` role, preserving every existing field (all others were
  already Vault defaults) so the other `vault-backend` ExternalSecrets were
  untouched → ExternalSecret `SecretSynced`, `cosign.pub` secret created.

## Lessons

1. **Seeding KV data is not sufficient — the ESO role's Vault policy must also grant
   `read` on the path.** A missing KV path *and* a missing policy grant produce the
   *same* `could not get secret data from provider` error. Always check both layers:
   `vault kv get` the path, and `vault read auth/kubernetes/role/<role>` to confirm
   the policy list includes one that reads it.
2. **Never regenerate signing material to "fix" a missing cosign secret.** Restore
   the original key from the Keychain backup. `signing_init` /
   `deploy_image_signing` regenerate and clobber the backup — running them turns a
   recoverable incident into permanent key loss.
3. **`security -w` hex-encodes multi-line values** (the PEM private key). Decode with
   `xxd -r -p`; single-line values (the password) come back plain. Detect by testing
   for the PEM `BEGIN` marker before deciding whether to hex-decode.
4. **`SecretSyncedError` contains the substring `SecretSynced`** — `grep -v
   SecretSynced` wrongly hides the *error* condition. Match `grep -v 'SecretSynced'`
   (trailing space/quote) or check the condition reason explicitly.
5. **stdin/fd-0 collision:** `{ printf secrets } | kubectl exec -i pod -- sh -s
   <<'EOF'` fails — the heredoc and the pipe both claim fd 0, and the piped token
   gets executed as a command (→ 403). Correct pattern: put the script in argv
   (`sh -c '<script>'`) and read secrets from stdin via `IFS= read -r` — secrets
   never appear in argv or logs.

## Follow-up

- **Mechanism of loss — RESOLVED** (see Confirmed mechanism above): full cluster
  rebuild wiped Vault's raft store; grafana KV data and the cosign
  data/policy/role-grant have no automatic bring-up seeder. This is a recurring
  exposure — it recurs on **every** cluster rebuild, not a one-off.
- **Give both secrets an idempotent, restore-from-backup bring-up seeder** so a
  missing path self-heals to a synced state instead of needing manual remediation:
  - **grafana:** have the observability bring-up seed `secret/observability/grafana`
    from the Keychain/k8s backup (matching the rotator `restore()` schema) when the
    path is absent — the writer role/policy are already created there; only the data
    write is missing. Do not rely on the rotator CronJob (it cannot bootstrap an
    empty path — its `restore()` reads the old password under `set -eu`; a 404 aborts).
  - **cosign:** add a **restore** path (distinct from `signing_init`'s regenerate)
    that re-seeds `secret/cosign/signing` from the `k3d-manager-signing` Keychain
    backup and re-applies the `cosign-verify` policy + ESO role grant when absent,
    without touching the keypair. `signing_init` / `deploy_image_signing` must never
    be the recovery path — they regenerate and clobber the Keychain backup.
- **Consider enabling a Vault audit device** so future secret loss has a per-operation
  trail (none was enabled here, so the KV `created_time` metadata was the only
  evidence).
