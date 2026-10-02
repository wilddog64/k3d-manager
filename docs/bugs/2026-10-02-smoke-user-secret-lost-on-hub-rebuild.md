# `identity/k3dm-smoke-user` is lost on every hub rebuild: the smoke credentials live only in a hand-made Secret

**Filed:** 2026-10-02
**Branch:** `k3d-manager-v1.40.0` (k3d-manager) + `fix/k3dm-smoke-user-externalsecret` (shopping-cart-infra)
**Severity:** low. Every k3s-hostinger `/cluster-status` ends `WARN (2 warnings)` on a healthy stack:

```
! Keycloak smoke token (k3dm-smoke-user): k3dm-smoke-user via identity/k3dm-smoke-user Secret: credentials unavailable
! Frontend API (smoke token): k3dm-smoke-user via identity/k3dm-smoke-user Secret: token unavailable
```

**Status:** FIXED (deployed 2026-10-02; `/cluster-status` 21 ok / 0 warn)
**Related:**
- `docs/bugs/2026-09-13-hub-recovery-manual-fixes-not-declarative.md` (Defect 6): it added the seed to
  `hub_recovery_reconcile`, which covers a restore but not a plain rebuild.
- `docs/issues/2026-09-11-status-warnings-hub-vault-eso-breakage.md`: the same Secret absent, re-seeded by hand.

## Cause

On the hub (`k3d-k3d-cluster`), `kubectl -n identity get secret k3dm-smoke-user` is `NotFound`. The
`identity` namespace was recreated 2026-09-20 by a hub rebuild.

The Secret is not ESO-managed. `keycloak_seed_smoke_user` and `keycloak_provision_shopping_cart_realm`
(`scripts/plugins/keycloak.sh`) write it with `kubectl create secret … | kubectl apply`. The password
exists **only** in that Secret, so a rebuild loses it and nothing recreates it. Every other identity
credential is an ExternalSecret over Vault and comes back on its own.

## Fix — option 2: Vault is the source of truth, ESO recreates the Secret

Vault path: KV v2 mount `secret`, key **`keycloak/smoke-user`**, fields `username`, `password`, `realm`,
`client`. The `eso-ldap-directory` role used by `identity/vault-kv-store` already reads
`secret/data/keycloak/*` (`LDAP_VAULT_POLICY_PREFIX` includes `keycloak`), so **no Vault policy change**.

## Resolution

Claude's verification fixes: the payload password moved from `jq --arg` argv to `$ENV`. In the smoke tests, mid-test `! grep` assertions
were silent no-ops under bats `set -e`; they now end with `|| false`. The stub's argv log flattens newlines. A
whole-line source grep was dropped. The argv-leak and Secret-create mutations are now red.

The smoke seed and realm-provision functions now use Vault `secret/keycloak/smoke-user` as the
source of truth, migrating a legacy password when necessary and generating one only when both
Vault and the old Secret are empty. They no longer create the Kubernetes Secret; an unowned legacy
Secret is removed after a successful Vault write, while ESO-owned Secrets are preserved. The
shopping-cart identity kustomization now declares the ESO ExternalSecret that recreates
`identity/k3dm-smoke-user` from Vault after a rebuild.

### A. k3d-manager — `scripts/plugins/keycloak.sh` (+ `scripts/tests/plugins/keycloak.bats`)

1. Add `_keycloak_smoke_vault_get_password` and `_keycloak_smoke_vault_put <payload_file>`, using the
   pattern already in `scripts/plugins/hub_recovery.sh` `_hub_recovery_mirror_argocd_admin`:
   - Root token from Secret `${VAULT_NS:-secrets}/vault-root`, key `root_token`.
   - `_no_trace _kubectl -- -n <vault ns> exec -i vault-0 -- sh -c 'read -r VAULT_TOKEN; export VAULT_TOKEN; vault kv … -mount=secret keycloak/smoke-user …'`.
   - The token is sent on **stdin**. For the put, the JSON payload is sent on stdin too (`vault kv put -mount=secret keycloak/smoke-user -`).
   - **No token or password in any argv**, and no `set -x` exposure.
   - The payload file is built with `jq -n --arg …` in the function's existing `mktemp -d` work dir, which the RETURN trap already removes.
   - The get prints the password or nothing, and never fails the caller.
2. In **both** `keycloak_seed_smoke_user` and `keycloak_provision_shopping_cart_realm`, choose the password in this order:
   1. Vault `keycloak/smoke-user` `password`.
   2. The existing k8s Secret's `password` (a one-time migration from the old layout).
   3. `openssl rand -hex 24`.
3. After Keycloak/LDAP accept the password (where each function writes the Secret today), write
   Vault `keycloak/smoke-user` with `username`, `password`, `realm` and `client`. `keycloak_seed_smoke_user` has `$realm` and `$client_id` too.
   - **Stop creating the k8s Secret.** Remove the `kubectl create secret` in `keycloak_provision_shopping_cart_realm` and the call to `_keycloak_smoke_write_secret`, and delete that function if nothing else uses it.
   - If `identity/k3dm-smoke-user` exists **without** `ownerReferences` (a leftover hand-made Secret), delete it so ESO can create its own. Leave an ESO-owned one alone.
   - Vault write fails → `_warn "[keycloak] could not store smoke credentials in Vault secret/keycloak/smoke-user"` and return 0 (keep the function's warn-and-return-0 contract).
   - Update the two `_info` lines to say `stored in Vault secret/keycloak/smoke-user`.
4. Update both help texts to say where the credentials now live.
5. Do not touch `scripts/lib/webhook/smoke.py`: it keeps reading `identity/k3dm-smoke-user` with keys `username`/`password`/`realm`, which ESO now produces.

### B. shopping-cart-infra — `identity/keycloak/` (branch `fix/k3dm-smoke-user-externalsecret`, already checked out)

1. New `identity/keycloak/k3dm-smoke-user-externalsecret.yaml`, modelled on
   `keycloak-client-secrets-externalsecret.yaml`:
   - name/target `k3dm-smoke-user`, namespace `identity`, sync-wave `"0"`, the same label set with `app.kubernetes.io/name`/`instance` = `k3dm-smoke-user`;
   - `refreshInterval: 15m`, store `vault-kv-store` (`SecretStore`), `creationPolicy: Owner`, type Opaque;
   - `data`: `username`, `password`, `realm`, `client` ← `secret/data/keycloak/smoke-user` property of the same name.
   - Header comment: "Seeded by k3d-manager keycloak_seed_smoke_user."
2. Add it to `resources:` in `identity/keycloak/kustomization.yaml`, after `keycloak-client-secrets-externalsecret.yaml`.
3. Nothing else in that repo changes.

## Tests (k3d-manager `scripts/tests/plugins/keycloak.bats`, stubbed; no cluster)

Stub `_kubectl`, `_curl` and the smoke helpers the way the existing smoke tests in that file do. Record
every `_kubectl` argv and stdin to a file.

- Seed with Vault holding a password → that password is set in Keycloak, and no `openssl rand` runs.
- Seed with Vault empty but a legacy Secret holding a password → that password is reused and written to Vault.
- Seed with both empty → a new password is written to Vault with all four fields (`username`, `password`, `realm`, `client`).
- No `_kubectl … create secret generic k3dm-smoke-user` is issued, from either function.
- **Secret hygiene:** neither the root token value nor the password value appears in any recorded `_kubectl` **argv**; they appear only on stdin.
- A Vault write failure → a warning naming `secret/keycloak/smoke-user`, and rc 0.
- An unowned legacy Secret is deleted; one with `ownerReferences` is not.

Infra: `kustomize build identity/keycloak` succeeds, and the output contains `kind: ExternalSecret` named
`k3dm-smoke-user` with `key: secret/data/keycloak/smoke-user`.

Mutations, each red, then `cp`-restored and `cmp`-proved:
(a) put the password in the `vault kv put` argv (`password=$password`) → the hygiene test is red;
(b) skip the Vault read → the reuse test is red;
(c) restore the `kubectl create secret` → the no-create test is red.

## Rules

- `bats scripts/tests/plugins/keycloak.bats scripts/tests/plugins/hub_recovery.bats` is green.
- `shellcheck scripts/plugins/keycloak.sh`: no new warnings compared with HEAD.
- `kustomize build` (or `kubectl kustomize`) on `identity/keycloak` succeeds.
- No cluster, network, Vault or git commits. Leave both repos' changes uncommitted.
- Update this doc: Status FIXED (pending deploy) plus a short Resolution section.
- Do not touch `CHANGELOG.md`; Claude adds the bullet.

## Rollout (operator, after merge)

1. Claude opens the shopping-cart-infra PR. ArgoCD tracks `main`, so the ExternalSecret appears only after merge.
2. **Rotate while migrating.** On 2026-10-02 the operator ran the *old* seed, which recreated a hand-made Secret.
   Claude then leaked that password into a session transcript, through a failing `kubectl -o go-template` on the
   Secret. So delete it first, and the seed generates a fresh password instead of migrating the exposed one:
   `kubectl --context k3d-k3d-cluster -n identity delete secret k3dm-smoke-user`, then
   `KEYCLOAK_BASE_URL=https://keycloak.3ai-talk.org ./scripts/k3d-manager keycloak_seed_smoke_user`.
   Vault is written, and ESO creates the Secret within 15m; annotate `force-sync` to make it immediate.
3. `/cluster-status` → 21 ok / 0 warn, and `ESO ExternalSecrets` on the hub counts the new one.

**Out of scope:** the Keycloak *user* itself. It lives in the Keycloak DB. If a future rebuild loses it, the
smoke token check now FAILs with HTTP 401, which is louder and points straight to the seed command, rather than a WARN that
reads "credentials unavailable".
