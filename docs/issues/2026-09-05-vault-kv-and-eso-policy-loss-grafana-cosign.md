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

Why these specific paths and the one policy grant disappeared from a healthy Vault
(rather than broad data loss) is **unconfirmed** — see Follow-up. The scoped,
surgical nature of the loss suggests these paths were simply never re-bootstrapped
after some Vault lifecycle event, not a general wipe.

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

- **Confirm the mechanism of loss (open).** Determine why `secret/observability/grafana`,
  `secret/cosign/signing`, and the `cosign-verify` policy grant vanished while the
  rest of Vault stayed intact. Rule out a partial restore, an unseal/re-init event,
  or a namespace/mount recreation.
- **Add an idempotent bootstrap/reconcile guard** so these required KV paths and the
  ESO policy grants are re-seeded (not regenerated) on startup if absent — a missing
  path should self-heal to a synced state rather than requiring manual remediation.
  Note: `grafana-credential-rotator` can rotate but cannot bootstrap an empty path
  (its `restore()` reads the old password under `set -eu`; a 404 aborts).
