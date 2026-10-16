# Bug: `hub_data_recover` Steps 6–7 fail on a fresh hub (shim scope, refresh order, PVC field ownership)

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.2`
**Status:** VERIFIED — Claude offline: tests green, new tests red on the old code, mutations red. Awaiting live proof. Was: IMPLEMENTED — landed `68aa8aa1` (Codex `2523ad56`); Claude verified the Step 7 order, server-side claim apply, 179/179, own D1 mutation red. Pending the 2026-10-29 live drill.
**Priority:** P2 — each one stops the restore; each has a manual workaround (below)
**Approval:** explicit 2026-10-15 "you can dispatch four recovery fixes to codex" (operator)
**Severity:** high — the first real `hub-recover-all` on a fresh hub needed three manual interventions in Steps 6–7

Live run `20261016T012103Z`, 2026-10-15. Related bugs filed from the same run:

- `2026-10-15-hub-recover-all-checks-keychain-after-deleting-the-hub.md`
- `2026-10-15-hub-only-rebuild-never-creates-the-identity-application.md`
- `2026-10-15-hub-recover-all-overwrites-the-dr-shards-its-restore-needs.md`

## D1 — `security` shim function references an out-of-scope `local`

**Symptom (Step 6, Re-point Vault):**

```text
scripts/plugins/hub_data.sh: line 879: shim: unbound variable
ERROR: [hub-recovery] Keychain service k3dm-vault-root-token could not be read back; unlock the login keychain: security unlock-keychain, then re-run make hub-recover
```

**Cause:** `_hub_data_install_credential_guard` (`scripts/plugins/hub_data.sh:863`) declares
`local ... shim=...`, then defines `security() { "$shim" "$@"; }`. The function body is expanded
when it is called, after the guard has returned, so `$shim` is unset. Under `set -u` every
`security` call afterwards fails. The Keychain error then blames a locked keychain, which is
misleading. This came in with v1.43.1 (`38fbf3ab`). No earlier run reached Step 6.

**Workaround:** `shim="$PWD/scripts/etc/dr/security-shim" REDO_STEP=6 RESUME=<run_id> ./scripts/k3d-manager hub_data_recover`

**Fix:** keep the shim path in a global, for example `_HUB_DATA_SECURITY_SHIM`, and use it in the
function body. Or drop the function, since `${run_dir}/bin/security` is already first on `PATH`.
Test: call `security` from a function that runs after the guard returns, under `set -u`.

## D2 — Step 7 restarts Keycloak before it force-syncs the ExternalSecrets

**Symptom (Step 7, Refresh dependents):**

```text
Error from server (NotFound): deployments.apps "keycloak" not found
kubectl command failed (1): kubectl --context k3d-k3d-cluster -n identity rollout restart deployment/keycloak
```

**Cause:** `_hub_data_refresh_dependents` (`scripts/plugins/hub_data.sh:789`) runs
`rollout restart deployment/keycloak || return 1`, then the
`annotate externalsecret --all -A force-sync=...`. On a fresh hub, `keycloak-secrets` last failed
while Vault was still the new, empty one, and it would not retry for up to 15 minutes. With no
secret, `postgres-keycloak` stays in `CreateContainerConfigError`, ArgoCD never creates
`deployment/keycloak`, and the restart fails before the force-sync that would fix it.

**Workaround:** run the force-sync annotate by hand, wait for `SecretSynced`, then resume.

**Fix:** force-sync first. Wait for the identity ExternalSecrets to reach `SecretSynced`, then
restart `deployment/keycloak` only if it exists. If it does not exist, wait for ArgoCD to create
it, with a bounded timeout and a clear message.

## D3 — the restored PVC hands `storageClassName` to ArgoCD, so the identity sync can never finish

**Symptom:** `shopping-cart-identity` is `OutOfSync`, and its operation `Failed` after 5 retries:

```text
PersistentVolumeClaim "postgres-keycloak-pvc" is invalid: spec: Forbidden: spec is immutable after creation ...
-   StorageClassName: &"local-path",
+   StorageClassName: nil,
```

`Deployment/keycloak` is never created.

**Cause:** Step 4 (`scripts/plugins/hub_data.sh:635`) recreates `postgres-keycloak-pvc` from the export's `pv-pvc.yaml` with a
client-side `kubectl apply`. That writes `storageClassName: local-path` into
`kubectl.kubernetes.io/last-applied-configuration`. The identity Application syncs with
`ServerSideApply=true`, and ArgoCD's client-side-to-server-side migration gives `argocd-controller`
ownership of every field in that annotation (`managedFields`: `argocd-controller Apply` owns
`f:storageClassName`). The `shopping-cart-infra` manifest does not set `storageClassName`, so each
apply tries to remove it, and a bound PVC spec is immutable. This is a new route to the failure in
`2026-09-23-argocd-identity-replace-true-cannot-update-bound-pvc.md`; the `Replace=true` cause
fixed there (F1, `e08eaa83`) is not involved.

**Workaround (used on this run):**

```bash
kubectl --context k3d-k3d-cluster -n identity annotate pvc postgres-keycloak-pvc kubectl.kubernetes.io/last-applied-configuration-
printf '%s\n' 'apiVersion: v1' 'kind: PersistentVolumeClaim' 'metadata: {name: postgres-keycloak-pvc, namespace: identity}' 'spec: {storageClassName: local-path}' \
  | kubectl --context k3d-k3d-cluster apply --server-side --field-manager=k3dm-hub-restore --force-conflicts -f -
kubectl --context k3d-k3d-cluster -n cicd patch app shopping-cart-identity --type merge -p '{"operation":{"initiatedBy":{"username":"operator"},"sync":{"syncOptions":["ServerSideApply=true"]}}}'
```

After this, `storageClassName` was owned by `k3dm-hub-restore`, the sync went `Synced`, and
`deployment/keycloak` was created.

**Fix:** in Step 4, create restored claims with `kubectl apply --server-side
--field-manager=k3dm-hub-restore` (or `kubectl create`), never client-side apply, so no
`last-applied-configuration` is written. Apply the same rule to the other two restored claims
(`data-vault-0`, `data-openldap-0`). Test: assert the restore's apply argv for claims.

## Fix spec (exact; covers D1–D3 and the Grafana, ArgoCD, export-SA and credential-audit notes)

All edits are in `scripts/plugins/hub_data.sh` unless stated.

### F1 — D1, shim scope (`_hub_data_install_credential_guard`)

Old: `  local run_dir="$1" context="$2" shim="${_HUB_DATA_ROOT}/scripts/etc/dr/security-shim"`

New (two lines):

```bash
  local run_dir="$1" context="$2"
  _HUB_DATA_SECURITY_SHIM="${_HUB_DATA_ROOT}/scripts/etc/dr/security-shim"
```

Old: `  ln -sf "$shim" "${shim_dir}/security"` → New: `  ln -sf "$_HUB_DATA_SECURITY_SHIM" "${shim_dir}/security"`

Old: `  security() { "$shim" "$@"; }` → New: `  security() { "$_HUB_DATA_SECURITY_SHIM" "$@"; }`

### F2 — D2, refresh order, plus Grafana and ArgoCD restarts (`_hub_data_refresh_dependents`)

Replace the two lines after the drill early-return:

```bash
  _kubectl --context "$context" -n identity rollout restart deployment/keycloak || return 1
  _kubectl --context "$context" annotate externalsecret --all -A "force-sync=$(date +%s)" --overwrite
```

with:

```bash
  local waited=0 limit="${K3DM_HUB_DATA_KEYCLOAK_WAIT_S:-600}"
  _kubectl --context "$context" annotate externalsecret --all -A "force-sync=$(date +%s)" --overwrite || return 1
  _kubectl --context "$context" -n identity wait externalsecret --all --for=condition=Ready --timeout=180s || return 1
  until _kubectl --no-exit --context "$context" -n identity get deployment/keycloak >/dev/null 2>&1; do
    (( waited >= limit )) && { _err "[hub-recover] deployment/keycloak not created by ArgoCD within ${limit}s; check the shopping-cart-identity Application"; return 1; }
    sleep "${K3DM_HUB_DATA_KEYCLOAK_POLL_S:-10}"; waited=$(( waited + ${K3DM_HUB_DATA_KEYCLOAK_POLL_S:-10} ))
  done
  _kubectl --context "$context" -n identity rollout restart deployment/keycloak || return 1
  _kubectl --context "$context" -n monitoring rollout restart deployment/kube-prometheus-stack-grafana || _warn "[hub-recover] could not restart Grafana; its admin password may not match Vault until it restarts"
  _kubectl --context "$context" -n cicd rollout restart deployment/argocd-server || _warn "[hub-recover] could not restart argocd-server; SSO may use a stale client secret until it restarts"
```

### F3 — D3, restored claims use server-side apply (Step 4 claim restore, the line ending `| _kubectl --context "$context" apply -f -` that writes a `PersistentVolumeClaim`)

Old ending: `| _kubectl --context "$context" apply -f -`

New ending: `| _kubectl --context "$context" apply --server-side --field-manager=k3dm-hub-restore -f -`

Only that line. The `hub-data-export` ServiceAccount line (`create sa ... | _kubectl apply -f -`) is unchanged.

### F4 — export ServiceAccount reminder (`_hub_data_recover_step9`)

Before `_hub_data_run_step "$steps" 9 true`, add:

```bash
  printf '%s\n' '[hub-recover] next: make hub-data-export-setup && make hub-data-export (the rebuilt hub has no hub-data-export ServiceAccount until setup runs)'
```

### F5 — credential allowlist (`scripts/etc/dr/credential-allowlist.tsv`)

After the line `restore-hub<TAB>add<TAB>k3d-manager-vault-unseal<TAB>secrets/vault:*`, add (tab-separated):

```text
restore-hub	find	k3d-manager-vault-unseal	secrets/vault:*
```

### F6 — tests (`scripts/tests/plugins/hub_data.bats`)

1. D1: install the guard inside a function, return, then call `security show-keychain-info` under
   `set -u` with the shim path stubbed. Assert it runs the shim and does not print `unbound variable`.
2. D2 order: with `_kubectl` logging its argv, assert the order is force-sync annotate, then
   `wait externalsecret`, then `get deployment/keycloak`, then the Keycloak restart, then the Grafana
   restart, then the `argocd-server` restart.
3. D2 wait: `get deployment/keycloak` fails twice, then succeeds (`K3DM_HUB_DATA_KEYCLOAK_POLL_S=0`).
   Assert the restart still happens. With it always failing and `K3DM_HUB_DATA_KEYCLOAK_WAIT_S=0`,
   assert rc 1 and the `not created by ArgoCD` message.
4. D2 Grafana restart failure → warning, rc 0.
5. D3: the claim-restore apply argv contains `--server-side` and `--field-manager=k3dm-hub-restore`.
6. F4: Step 9 output contains `make hub-data-export-setup`.
7. F5: the allowlist has the `restore-hub find k3d-manager-vault-unseal secrets/vault:*` row
   (parse the TSV fields; do not grep a whole line).

Never use a bare mid-test `! grep`; use `run ! grep` or `|| false`. Mutation: on snapshots,
(a) swap the D2 restart back before the annotate and show test 2 red; (b) drop
`--server-side` and show test 5 red. Restore each and `cmp`.

### F7 — docs

`docs/howto/hub-dr-drill.md` recovery runbook: Step 7 now force-syncs secrets, waits for
Keycloak and restarts Keycloak, Grafana and `argocd-server`; after the report, run
`make hub-data-export-setup && make hub-data-export`.

## Files

- `scripts/plugins/hub_data.sh`
- `scripts/etc/dr/credential-allowlist.tsv`
- `scripts/tests/plugins/hub_data.bats`
- `docs/howto/hub-dr-drill.md`

## Definition of Done

- [ ] F6 tests 1–7 pass; tests 2 and 5 are shown red under their mutations.
- [ ] `shellcheck scripts/plugins/hub_data.sh` has no new warnings; the hub_data, vault_dr_shards and hub_recovery suites are green.
- [ ] Live: the 2026-10-29 rebuild drill passes Steps 6–7 with no manual step.
- [ ] Commit message: `fix(hub-data): recover Steps 6-7 on a fresh hub (shim scope, refresh order, claim ownership)`

## Related notes from the same run

- **Grafana admin password mismatch.** `hub-restore` Step 3 seeds a fresh Grafana admin password
  into the *new* Vault, and ESO syncs it into `grafana-admin-credentials`. The data restore then
  brings back the *old* Vault value. `make show-service-passwords` reads Vault, so it shows a
  password that Grafana does not accept. Grafana runs on an `emptyDir`, so a force-sync of the
  ExternalSecret followed by `rollout restart deploy/kube-prometheus-stack-grafana` fixes it.
  Step 7 should restart Grafana (and `argocd-server`, which also reads ESO-fed OIDC settings)
  after its force-sync.
- **Credential audit.** `credentials_unexpected.tsv` recorded 2 `find` calls on
  `k3d-manager-vault-unseal` `secrets/vault:count`, from Step 6 `_vault_cache_unseal_keys`. Either
  add the entry to `scripts/etc/dr/credential-allowlist.tsv` for the `restore-hub` scope, or stop
  Step 6 from reading the cache.
- **The export ServiceAccount is not recreated.** After the recovery, `make hub-data-export` failed with
  `serviceaccounts "hub-data-export" not found`, then `could not record the inventory ...; nothing was
  pushed`. The SA (and the Vault `hub-data-inventory` policy and role) come from
  `hub_data_export_setup` (`make hub-data-export-setup`), which the recovery never runs. Until
  then, the scheduled export also fails. Fix: the recovery's final step runs `hub_data_export_setup`
  (it is idempotent and self-tests).
