# Bug: the hub-only rebuild never creates the `shopping-cart-identity` Application, so `hub-recover-all` cannot restore

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.2`
**Status:** VERIFIED — Claude offline: tests green, new tests red on the old code, mutations red. Awaiting live proof. Was: IMPLEMENTED — landed `ffe7ce6a` (Codex `30fb784c`); Claude verified byte-identical manifest, 229/229 combined (one intermittent pty failure in pre-existing hub_restore TTY tests, 0/12 on rerun on both trees), own mutation red. Pending the 2026-10-29 live drill.
**Priority:** P2 — `hub-recover-all` cannot finish on a fresh hub; a manual apply (below) unblocks it
**Approval:** explicit 2026-10-15 "you can dispatch four recovery fixes to codex" (operator)
**Severity:** high — the recovery path built in `0214f363` stops before the data restore on every fresh hub

## Symptom

Live run `20261016T012103Z` (2026-10-15). After the teardown and `hub-up`, `make hub-restore`
ended:

```text
[hub-restore] 5/9 Hub reconcile            FAIL
```

with:

```text
Error from server (NotFound): applications.argoproj.io "shopping-cart-identity" not found
kubectl command failed (1): kubectl --context k3d-k3d-cluster -n cicd patch application shopping-cart-identity ...
```

The `RESUME` restore then refused at Step 1/9, because its target check needs
`identity/deployment/postgres-keycloak`:

```text
Error from server (NotFound): deployments.apps "postgres-keycloak" not found
```

## Root cause

The `shopping-cart-identity` Application (Keycloak plus `postgres-keycloak`, sourced from
`shopping-cart-infra` `identity/keycloak`) is created in one place only: the inline manifest in
`bin/cluster-up` Step 10c (`bin/cluster-up:1039`). `services-git` deliberately excludes
`services/shopping-cart-identity`, and no ApplicationSet generates it.

The hub-only path is `bin/hub-up` (cluster, Vault, LDAP, ArgoCD), then `make observability`,
`platform-ops` and `bin/hub-restore`. None of them creates the Application.
`_hub_recovery_replay_identity_hook` (`scripts/plugins/hub_recovery.sh:136`) assumes it exists and
patches it. So on a fresh hub, nothing deploys Keycloak, and `hub_data_recover` cannot run.

Earlier recoveries passed because the hub they ran against still had the Application from an
earlier `cluster-up`.

## Workaround (used on run `20261016T012103Z`)

```bash
./scripts/k3d-manager keycloak_smoke_vault_preseed
# the exact manifest from bin/cluster-up Step 10c, extracted unchanged
kubectl --context k3d-k3d-cluster apply -f identity-app.yaml
# wait until deploy/postgres-keycloak and deploy/keycloak are available (~4 min)
RESUME=<run_id> ./scripts/k3d-manager hub_data_recover
```

The data restore brings back the Keycloak database (realm and users), so the realm import in
`bin/cluster-up` Step 10d is not needed on this path.

## Fix (covers this section and the two "Also missing" sections below)

### F1 — new file `scripts/etc/argocd/identity/shopping-cart-identity-application.yaml`

Move the `shopping-cart-identity` Application out of the `bin/cluster-up` Step 10c heredoc,
**byte for byte**: everything between `kubectl apply --context k3d-k3d-cluster -f - <<'IDEOF'` and
`IDEOF`. Do not change any field.

### F2 — `bin/cluster-up` Step 10c

Replace the whole heredoc, from the `kubectl apply --context k3d-k3d-cluster -f - <<'IDEOF'` line
through the closing `IDEOF` line, with:

```bash
kubectl apply --context k3d-k3d-cluster -f "${REPO_ROOT}/scripts/etc/argocd/identity/shopping-cart-identity-application.yaml"
```

Keep the comment line above it and everything after it unchanged.

### F3 — `scripts/plugins/hub_recovery.sh`: identity bootstrap on the hub-only path

Add this function directly above `function _hub_recovery_retry_failed_identity_sync()`:

```bash
function _hub_recovery_ensure_identity_bootstrap() {
  local hub_context="$1"
  local app_file="${SCRIPT_DIR}/etc/argocd/identity/shopping-cart-identity-application.yaml"
  local oidc_es="${HUB_RECOVERY_INFRA_ROOT:-${SCRIPT_DIR}/../../shopping-carts/shopping-cart-infra}/argocd/config/argocd-secret.yaml"
  if ! _kubectl --no-exit --context "$hub_context" -n cicd get application shopping-cart-identity >/dev/null 2>&1; then
    _info "[hub-recovery] shopping-cart-identity Application missing; applying ${app_file}"
    _kubectl --context "$hub_context" apply -f "$app_file" || return 1
  fi
  if [[ -f "$oidc_es" ]]; then
    _kubectl --context "$hub_context" apply -f "$oidc_es" || return 1
  else
    _warn "[hub-recovery] ${oidc_es} not found; ArgoCD SSO needs ExternalSecret cicd/argocd-oidc-secret from shopping-cart-infra"
  fi
}
```

In `hub_recovery_reconcile`, call it immediately before the existing
`_hub_recovery_retry_failed_identity_sync "$hub_context"` line:

```bash
  _hub_recovery_ensure_identity_bootstrap "$hub_context" || return 1
```

Add `"Identity Application + ArgoCD OIDC secret"` as the **first** entry of the `steps=(...)`
listing array in `hub_recovery_reconcile`. Update any test that counts or prints that list.

### F4 — `bin/hub-restore` Step 8: ArgoCD and Keycloak port-forward agents

Add this helper directly above the `_step_start 8` line:

```bash
_hub_restore_ensure_pf_agent() {
  local name="$1" label="com.k3d-manager.$1-port-forward" state_dir wrapper plist log
  state_dir="$(_acg_provider_state_dir k3s-aws)"
  wrapper="${state_dir}/bin/${name}-port-forward.sh"
  plist="${HOME}/Library/LaunchAgents/${label}.plist"
  log="${state_dir}/logs/${name}-pf.log"
  if [[ ! -f "${wrapper}" ]]; then
    _info "[hub-restore] ${label}: wrapper ${wrapper} missing; run make up once to generate it"
    return 1
  fi
  if [[ ! -f "${plist}" ]]; then
    mkdir -p "$(dirname "${log}")" "$(dirname "${plist}")"
    cat > "${plist}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${wrapper}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${log}</string>
  <key>StandardErrorPath</key>
  <string>${log}</string>
</dict>
</plist>
PLIST
  fi
  launchctl list "${label}" >/dev/null 2>&1 && return 0
  launchctl bootstrap "gui/$(id -u)" "${plist}"
}
```

In Step 8, after the `install-hub-pushgateway-port-forward` line, add:

```bash
for _pf_name in argocd keycloak; do
  _hub_restore_ensure_pf_agent "${_pf_name}" || _local_agents_ok=0
done
```

This is the same plist that `bin/cluster-refresh` writes, so either path can manage the agent.

### F5 — tests

- `scripts/tests/bin/cluster_up.bats`: the two tests that extract the `IDEOF` heredoc now read
  `scripts/etc/argocd/identity/shopping-cart-identity-application.yaml` instead. Keep their
  assertions: `syncOptions` == `["CreateNamespace=true", "ServerSideApply=true"]`, the
  `ServerSideDiff=true` compare-options annotation, and no `Replace=true` anywhere. Add one test that
  `bin/cluster-up` applies that file and no longer contains `<<'IDEOF'`.
- `scripts/tests/plugins/hub_recovery.bats`: (a) Application absent → `apply -f` is called with the
  app file; (b) Application present → it is not applied; (c) the OIDC ExternalSecret file present
  (point `HUB_RECOVERY_INFRA_ROOT` at a temp dir) → `apply -f` is called with it; (d) file absent →
  warning, rc 0; (e) `hub_recovery_reconcile --confirm` calls the bootstrap before
  `_hub_recovery_retry_failed_identity_sync`.
- `scripts/tests/bin/hub_restore.bats`: with `HOME` and the state dir in temp dirs and
  `launchctl` stubbed: (a) wrapper present, plist absent, not loaded → plist written (passes
  `plutil -lint` if available, otherwise contains the wrapper path) and `bootstrap` called;
  (b) already loaded → no bootstrap; (c) wrapper missing → rc 1 and no plist.
- Mutation: remove the `_hub_recovery_ensure_identity_bootstrap` call from `hub_recovery_reconcile`
  on a snapshot; show test (e) red; restore and `cmp`.

### F6 — docs

`docs/howto/hub-rebuild-from-gitops-vault.md`, "Identity app stuck after a rebuild": say that
`make hub-recover` now creates the identity Application and the ArgoCD OIDC ExternalSecret, and
`make hub-restore` installs the ArgoCD and Keycloak port-forward agents.

## Also missing on the hub-only path: the ArgoCD and Keycloak port-forward agents

After the restore, `argocd.3ai-talk.org` and `keycloak.3ai-talk.org` returned 502. The tunnel sends
them to `127.0.0.1:8080` and `127.0.0.1:8880`. The teardown (`bin/cluster-down`) unloads and
deletes `com.k3d-manager.argocd-port-forward` and `com.k3d-manager.keycloak-port-forward`. Only
`bin/cluster-up` and `bin/cluster-refresh` install them, and `make refresh` also attempts an ACG
login. The wrapper scripts under `~/.local/share/k3d-manager/k3s-aws/bin/` survived.

**Workaround (used):** the two plists were generated from the `bin/cluster-refresh` template and
bootstrapped with `launchctl bootstrap gui/$(id -u)`. All three public URLs then returned 200.

**Fix:** the hub-only path (`bin/hub-restore` Step 8 "Local agents") installs both agents, reusing
the `bin/cluster-refresh` plist block through a shared helper.

## Also missing: the ArgoCD OIDC client-secret ExternalSecret

ArgoCD SSO then failed with `failed to get token: oauth2: "unauthorized_client" "Invalid client or
Invalid client credentials"`. `argocd-cm` references `$oidc.keycloak.clientSecret`, but
`argocd-secret` had no such key. The key comes from `ExternalSecret/argocd-oidc-secret`
(`shopping-cart-infra/argocd/config/argocd-secret.yaml`: Vault `secret/keycloak/clients`
`argocd_client_secret`, merged into `argocd-secret`). Only `bin/cluster-up` applies it, around
line 1559. The hub-only path never does.

**Workaround (used):** `kubectl apply -f ../shopping-carts/shopping-cart-infra/argocd/config/argocd-secret.yaml`,
wait for `SecretSynced`, then `rollout restart deploy/argocd-server`.

**Fix:** the same shared "identity bootstrap" step that applies the identity Application also
applies this ExternalSecret and restarts `argocd-server` once it syncs.

## Files

- `scripts/etc/argocd/identity/shopping-cart-identity-application.yaml` (new)
- `bin/cluster-up`
- `scripts/plugins/hub_recovery.sh`
- `bin/hub-restore`
- `scripts/tests/bin/cluster_up.bats`, `scripts/tests/plugins/hub_recovery.bats`, `scripts/tests/bin/hub_restore.bats`
- `docs/howto/hub-rebuild-from-gitops-vault.md`

## Definition of Done

- [ ] F5 tests pass; test (e) is shown red under the F5 mutation.
- [ ] The new YAML file is byte-identical to the removed heredoc body (show `diff` against the body extracted from `git show HEAD:bin/cluster-up` with the same sed).
- [ ] `shellcheck bin/cluster-up bin/hub-restore scripts/plugins/hub_recovery.sh` has no new warnings; the cluster_up, hub_recovery, hub_restore and hub_data suites are green.
- [ ] Live: the 2026-10-29 rebuild drill finishes `make hub-recover-all` with no manual identity, OIDC or port-forward step.
- [ ] Commit message: `fix(hub-recovery): bootstrap the identity app, ArgoCD OIDC secret and port-forwards on the hub-only path`
