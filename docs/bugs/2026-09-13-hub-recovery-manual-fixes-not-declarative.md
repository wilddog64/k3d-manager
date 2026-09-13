# Bug: hub recovery depends on manual fixes that no code path reproduces

**Filed:** 2026-09-13
**Branch:** `k3d-manager-v1.33.0`
**Incident:** `docs/issues/2026-09-11-hub-recovery-public-origin-and-eso.md`
**Status:** READY FOR CODEX — design decisions answered by the user 2026-09-13 (see "Decisions")

---

## Summary

The 2026-09-11 controlled hub rebuild reached a working state only after
hand-applied fixes. More gaps surfaced during the 2026-09-13 close-out. None of
these fixes is reproduced by bootstrap, refresh or `hub_recovery_*`, so the next
server-container rebuild will regress in the same ways:

- zero shopping-cart Applications
- `SecretSyncedError` on every app ExternalSecret
- Cloudflare 502 on `frontend.3ai-talk.org`
- CVE panel without hostinger data
- broken Keycloak federation
- no smoke-login credentials

The user's direction (2026-09-13): *"re-seed but also need to store root token in
keychain so next time we can rebuild easier. these should be automated"*.

## Decisions (answered 2026-09-13)

| # | Question | Answer |
|---|----------|--------|
| 1 | Hub in-cluster registration entry point | Extend `register_app_cluster`: no token when `ARGOCD_APP_CLUSTER_SERVER=https://kubernetes.default.svc` |
| 2 | Vault access for app secret prefixes | A second `eso-apps` policy on the existing ESO role `eso-ldap-directory` |
| 3 | Cloudflare origins | A provider-keyed origin table in `scripts/etc/cloudflared/` |
| 4 | Where the fixes run | A separate `hub_recovery_reconcile [--confirm]` that runs after PV restore |
| 5 | Vault root token | Back it up to the macOS Keychain; reconcile restores `secrets/vault-root` from it when absent |

## Defects

### Defect 1 — hub-as-app-cluster registration is not recreated

Live (correct) state, 2026-09-13:

```text
secret cicd/ubuntu-k3s-app-cluster
  labels: argocd.argoproj.io/secret-type=cluster, k3d-manager/provider=k3d, k3d-manager/role=app-cluster
  stringData: name=ubuntu-k3s, server=https://kubernetes.default.svc, config={}
```

- `services-git` selects on `k3d-manager/role=app-cluster`; without this Secret it generates zero service Applications.
- `register_app_cluster` (`scripts/plugins/argocd.sh:1322`) already switches the environment to `infra` for the in-cluster server.
- It still hard-requires `ARGOCD_APP_CLUSTER_TOKEN`, though a token means nothing for `https://kubernetes.default.svc`.

### Defect 2 — app secret prefixes are absent from every ESO Vault policy

- The only ESO role, `eso-ldap-directory`, is written by `ldap.sh:1136` via `_vault_configure_secret_reader_role`. It covers only `ldap,keycloak,observability,platform-ops`.
- The live fix attached a hand-written `eso-apps` policy. Live role, 2026-09-13: `policies: [eso-apps, eso-ldap-directory]`.
- **Latent regression:** `_vault_configure_secret_reader_role` writes the role with `policies="$policy"`. Any re-run of the LDAP deploy silently detaches `eso-apps` again.
- Prefixes the hub ExternalSecrets read: `github/pat`, `minio`, `payment`, `postgres`, `rabbitmq`, `redis`.

### Defect 3 — static Cloudflare config carries one provider's frontend origin

- `bin/cluster-up:1723-1724` copies `scripts/etc/cloudflared/config.yml` to `~/.cloudflared/config.yml`. That copy has `frontend.3ai-talk.org → http://127.0.0.2:80`, the hostinger/ACG `frontend-browser-http` listener.
- The hub (k3d) frontend is served at `http://127.0.0.1:8000`: the k3d serverlb host port, published by OrbStack, which fronts the Istio ingress NodePort.
- Every other hostname's origin is the same across providers.
- `bin/public-endpoint-probe` reads only `hostname:` lines, so it needs no change.

### Defect 4 — the hostinger CVE reader credential is not re-seeded

- Vault KV `secret/platform-ops/app-cluster-hostinger` (`server`, `caData`, `bearerToken`) was absent after the rebuild. As a result, ExternalSecret `platform-ops/app-cluster-kubeconfig` failed and `hub-platform-ops` was Degraded.
- Re-seeded by hand on 2026-09-13 from the existing read-only SA `platform/hub-cve-inventory-reader`, using its long-lived token Secret `platform/hub-cve-inventory-reader-token`.
- Result: the exporter serves 62 shopping-cart CVE series.

### Defect 5 — the Vault root token exists only inside the cluster

- `secrets/vault-root` (`root_token`) is the only copy. Losing the cluster state loses the token.
- Hand-stored in the Keychain on 2026-09-13 as service `k3dm-vault-root-token`, account `k3d-k3d-cluster`.
- Nothing writes or reads that item in code.

### Defect 6 — post-restore identity state is left broken

- **OpenLDAP left at zero replicas.** `hub_recovery_restore` requires stateful consumers to be scaled down first, and nothing scales them back. `identity/sts/openldap` stayed at `replicas: 0`, although its Helm release declares `replicaCount: 1`. The `keycloak-realm-reconcile` hook then failed with `openldap.identity.svc.cluster.local:389 Connection refused`.
- **Hook never replayed.** The `shopping-cart-identity` PostSync hook needs a hook-inclusive sync after LDAP is back.
- **Smoke user not seeded.** `identity/k3dm-smoke-user` was absent, so `make status` reported "Keycloak login: no credentials". `keycloak_seed_smoke_user` defaults to `http://keycloak.shopping-cart.local`, which does not resolve on the hub (curl exit 7). It only worked with `KEYCLOAK_BASE_URL=https://keycloak.3ai-talk.org`.

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
- `git pull origin k3d-manager-v1.33.0` — work on that branch only.
- Read IN FULL before editing:
  - `scripts/plugins/argocd.sh` — `register_app_cluster` (1322-1420) and `_argocd_set_active_app_cluster` (1292)
  - `scripts/plugins/vault.sh` — `_vault_build_policy_hcl` (1991) and `_vault_configure_secret_reader_role` (2043)
  - `scripts/plugins/ldap.sh` — lines 1120-1145
  - `scripts/plugins/keycloak.sh` — `_keycloak_smoke_base_url` (376) and `keycloak_seed_smoke_user` (486)
  - `scripts/plugins/hub_recovery.sh` — the whole file
  - `scripts/tests/plugins/hub_recovery.bats`, `scripts/tests/plugins/argocd.bats` and `scripts/tests/plugins/vault.bats` — the stubbing idioms
  - `bin/cluster-up` — lines 1680-1730
- Cross-plugin rule: the dispatcher lazy-loads only the invoked plugin. `hub_recovery.sh` must source `argocd.sh`, `vault.sh` and `keycloak.sh` using the `VAULT_PLUGIN` idiom from `scripts/plugins/argocd.sh:7-11`. Never guard with `declare -f`.

## Changes

### C1 — `scripts/plugins/argocd.sh`: token-less in-cluster registration

Old:

```bash
  if [[ -z "${ARGOCD_APP_CLUSTER_TOKEN:-}" ]]; then
```

New:

```bash
  local _in_cluster=0
  [[ "${ARGOCD_APP_CLUSTER_SERVER:-}" == "https://kubernetes.default.svc" ]] && _in_cluster=1

  if (( ! _in_cluster )) && [[ -z "${ARGOCD_APP_CLUSTER_TOKEN:-}" ]]; then
```

Inside the existing `set +x` region (immediately after `case $- in *x*) _wasx=1; set +x;; esac`), add:

```bash
  local _config_json
  if (( _in_cluster )); then
    _config_json="{}"
  else
    printf -v _config_json '{\n      "bearerToken": "%s",\n      "tlsClientConfig": { %s }\n    }' \
      "${ARGOCD_APP_CLUSTER_TOKEN}" "${_tls_client_config}"
  fi
```

In the heredoc, replace:

```text
  config: |
    {
      "bearerToken": "${ARGOCD_APP_CLUSTER_TOKEN}",
      "tlsClientConfig": { ${_tls_client_config} }
    }
```

with:

```text
  config: |
    ${_config_json}
```

The remote-cluster rendering must stay byte-identical to today's output. In the help text, change `ARGOCD_APP_CLUSTER_TOKEN ... (required — no default)` to `(required unless SERVER=https://kubernetes.default.svc)`.

### C2 — `scripts/plugins/vault.sh`: `eso-apps` policy that survives LDAP re-runs

In `_vault_configure_secret_reader_role`, replace:

```bash
  printf -v role_cmd 'vault write "auth/kubernetes/role/%s" bound_service_account_names="%s" bound_service_account_namespaces="%s" policies="%s" ttl=1h token_audiences="%s"'      "$role" "$service_account" "$bound_namespaces" "$policy" "$token_audience"
```

with:

```bash
  local role_policies="$policy"
  local apps_policy="${VAULT_ESO_APPS_POLICY-eso-apps}"
  if [[ "$role" == "eso-ldap-directory" && -n "$apps_policy" ]]; then
     role_policies="${apps_policy},${policy}"
  fi
  printf -v role_cmd 'vault write "auth/kubernetes/role/%s" bound_service_account_names="%s" bound_service_account_namespaces="%s" policies="%s" ttl=1h token_audiences="%s"'      "$role" "$service_account" "$bound_namespaces" "$role_policies" "$token_audience"
```

Add a new function directly after `_vault_configure_secret_reader_role`:

```bash
function _vault_ensure_eso_apps_policy() {
  local ns="${1:-$VAULT_NS_DEFAULT}" release="${2:-$VAULT_RELEASE_DEFAULT}" mount="${3:-secret}"
  local policy="${VAULT_ESO_APPS_POLICY:-eso-apps}"
  local prefixes="${VAULT_ESO_APPS_PREFIXES:-github/pat,minio,payment,postgres,rabbitmq,redis}"
  local pod="${release}-0"
  local -a secret_prefixes=()
  read -r -a secret_prefixes <<< "${prefixes//,/ }"
  _vault_build_policy_hcl "${mount%/}" "${secret_prefixes[@]}"
  _vault_login "$ns" "$release"
  if ! printf '%s\n' "$_VAULT_POLICY_HCL" | _no_trace _vault_exec_stream --no-exit --stdin --pod "$pod" "$ns" "$release" -- vault policy write "$policy" -; then
     _err "[vault] failed to apply policy ${policy}"
     return 1
  fi
  _info "[vault] policy ${policy} applied (${prefixes})"
}
```

### C3 — `scripts/plugins/ldap.sh`: apply `eso-apps` on the bootstrap path

Directly after the `_vault_configure_secret_reader_role ... || { ... }` line at 1136, add:

```bash
   _vault_ensure_eso_apps_policy "$vault_ns" "$vault_release" "$LDAP_VAULT_KV_MOUNT" ||       { _err "[ldap] failed to apply eso-apps Vault policy"; return 1; }
```

### C4 — `scripts/plugins/keycloak.sh`: hub-reachable smoke base URL

Old:

```bash
   elif [[ "${CLUSTER_PROVIDER:-}" == "k3s-hostinger" ]]; then
```

New:

```bash
   elif [[ "${CLUSTER_PROVIDER:-}" == "k3s-hostinger" || "${CLUSTER_PROVIDER:-}" == "k3d" ]]; then
```

### C5 — `scripts/etc/cloudflared/origins.tsv` (new) and the origin override helper

New file `scripts/etc/cloudflared/origins.tsv` (tab-separated, `#` comments allowed):

```text
# hostname	provider	origin
frontend.3ai-talk.org	k3d	http://127.0.0.1:8000
frontend.3ai-talk.org	k3s-hostinger	http://127.0.0.2:80
frontend.3ai-talk.org	k3s-aws	http://127.0.0.2:80
```

Add to `scripts/plugins/hub_recovery.sh`. It is pure: no kubectl, no network.

```bash
function _hub_recovery_render_cloudflared_config() {
  local provider="$1" in_file="$2" table="$3"
  awk -v provider="$provider" -v table="$table" '
    BEGIN {
      while ((getline line < table) > 0) {
        if (line ~ /^#/ || line == "") continue
        split(line, f, "\t")
        if (f[2] == provider) origin[f[1]] = f[3]
      }
    }
    /^[[:space:]]*-[[:space:]]*hostname:/ { host = $NF; print; next }
    /^[[:space:]]*service:/ {
      if (host != "" && (host in origin)) sub(/service:.*/, "service: " origin[host])
      host = ""; print; next
    }
    { print }
  ' "$in_file"
}
```

In `bin/cluster-up`, replace:

```bash
      cp "${_cf_static_config}" "${_cloudflared_config}"
```

with:

```bash
      _hub_recovery_render_cloudflared_config "${CLUSTER_PROVIDER:-k3s-aws}" "${_cf_static_config}" \
        "${REPO_ROOT}/scripts/etc/cloudflared/origins.tsv" > "${_cloudflared_config}"
```

Also source `scripts/plugins/hub_recovery.sh` in `bin/cluster-up` next to its existing plugin sources.

### C6 — `scripts/plugins/hub_recovery.sh`: `hub_recovery_reconcile [--confirm]`

This is a new public function. Without `--confirm` it prints each numbered step and changes nothing. With `--confirm` it runs the steps in order and stops at the first failure. Every step is idempotent. Hub context `HUB_RECOVERY_HUB_CONTEXT` (default `k3d-k3d-cluster`); app reader context `HUB_RECOVERY_APP_CONTEXT` (default `ubuntu-hostinger`).

1. **Vault root token ↔ Keychain** (`_hub_recovery_sync_vault_root_token`, macOS only via `_is_mac`, otherwise skip with `_info`):
   - If Secret `secrets/vault-root` exists, write its `root_token` to Keychain service `k3dm-vault-root-token`, account `${HUB_RECOVERY_HUB_CONTEXT}`. Pass the value on stdin: `printf 'add-generic-password -U -s %s -a %s -w %s\n' ... | security -i >/dev/null`. It must never appear in argv.
   - Else, if the Keychain item exists, recreate `secrets/vault-root` from it. Build the manifest with `jq` and pipe it into `_kubectl apply -f -`; never use `--from-literal`.
   - Else `_err` and return 1.
2. **ESO policy:** `_vault_ensure_eso_apps_policy secrets vault secret`, then read the role and, if `eso-apps` is not in `token_policies`, re-run `_vault_configure_secret_reader_role` with the LDAP arguments from `ldap.sh:1136`. Source `scripts/etc/ldap/vars.sh` for them.
3. **Hub registration:** call `register_app_cluster` with these exports:
   - `ARGOCD_APP_CLUSTER_SERVER=https://kubernetes.default.svc`
   - `ARGOCD_APP_CLUSTER_NAME=ubuntu-k3s`
   - `ARGOCD_APP_CLUSTER_SECRET_NAME=ubuntu-k3s-app-cluster`
   - `ARGOCD_APP_CLUSTER_PROVIDER=k3d`
   - `ARGOCD_NAMESPACE=cicd`
4. **CVE reader credential** (`_hub_recovery_seed_app_cluster_reader`):
   - Read `server` from `kubectl config view -o jsonpath='{.clusters[?(@.name=="<app ctx>")].cluster.server}'`.
   - Read `caData` (the `ca.crt` field, as-is) and `bearerToken` (base64-decoded) from `platform/hub-cve-inventory-reader-token` on the app context.
   - Assert all three are non-empty with `jq -e`.
   - Pipe `root_token\nJSON` into `kubectl exec -i vault-0 -- sh -c 'read -r VAULT_TOKEN; export VAULT_TOKEN; vault kv put -mount=secret platform-ops/app-cluster-hostinger -'`.
   - If the app context or SA Secret is absent, `_warn` and skip; this step is not fatal.
5. **OpenLDAP replicas:** if `identity/sts/openldap` has `.spec.replicas == 0`, scale it to `HUB_RECOVERY_OPENLDAP_REPLICAS` (default `1`) and `rollout status --timeout=180s`.
6. **Identity hook replay:** merge-patch Application `cicd/shopping-cart-identity` with `{"operation":{"initiatedBy":{"username":"hub_recovery_reconcile"},"sync":{"prune":false,"syncStrategy":{"hook":{}}}}}`, then poll `.status.operationState.phase` (max 300s). Anything other than `Succeeded` is fatal.
7. **Smoke user:** `KEYCLOAK_BASE_URL="${KEYCLOAK_BASE_URL:-https://keycloak.3ai-talk.org}" keycloak_seed_smoke_user`.
8. **Cloudflare origins:**
   - Render `scripts/etc/cloudflared/config.yml` for provider `k3d` into a temp file.
   - If it differs from `~/.cloudflared/config.yml`, back up the old file to `~/.cloudflared/config.yml.bak.<UTC timestamp>` and install the new one.
   - Print the operator reload command `launchctl kickstart -k "gui/$(id -u)/com.k3d-manager.cloudflare-tunnel"`. Do NOT run launchctl.

Add `hub_recovery_reconcile` to the `hub_recovery_restore` final dry-run message: `Then run: hub_recovery_reconcile --confirm`.

## Tests (pure logic — no cluster mocks)

`scripts/tests/plugins/hub_recovery.bats`:

- `_hub_recovery_render_cloudflared_config k3d` changes only the frontend service to `http://127.0.0.1:8000`, and the output has the same line count as the input.
- `_hub_recovery_render_cloudflared_config k3s-hostinger` output equals the input byte-for-byte.
- An unknown provider yields output equal to the input.
- `hub_recovery_reconcile` without `--confirm` prints steps 1-8 and invokes none of the stubbed `_kubectl`, `security` or `register_app_cluster`.

`scripts/tests/plugins/vault.bats`:

- After `_vault_build_policy_hcl secret github/pat minio payment postgres rabbitmq redis`, `_VAULT_POLICY_HCL` contains `secret/data/redis/*` and `secret/data/github/pat`, contains no `create`, `update` or `delete`, and has no `secret/data/*` line.

`scripts/tests/plugins/argocd.bats` (stub `_kubectl` to copy the `-f` file and `_argocd_set_active_app_cluster` to a no-op, following that suite's idiom):

- With `SERVER=https://kubernetes.default.svc` and no token, it returns 0 and the rendered file has `config: |` followed by `{}` and no `bearerToken`.
- With a remote server and no token, it returns 1.

## Definition of Done

- [ ] C1-C6 implemented exactly; no other files changed
- [ ] `shellcheck -x` clean on `scripts/plugins/{argocd,vault,ldap,keycloak,hub_recovery}.sh` and `bin/cluster-up` (no new warnings)
- [ ] `bats scripts/tests/plugins/hub_recovery.bats scripts/tests/plugins/vault.bats scripts/tests/plugins/argocd.bats` green — paste the summary
- [ ] CHANGELOG `## [Unreleased]` → `### Fixed` entry: "hub recovery reconcile — in-cluster registration, eso-apps policy, CVE reader seed, Vault root token Keychain backup, OpenLDAP scale-up, identity hook replay, smoke user, provider-aware Cloudflare origins"
- [ ] Commit message verbatim: `fix(hub-recovery): add hub_recovery_reconcile to make post-restore fixes declarative`
- [ ] Commit on `k3d-manager-v1.33.0`, pushed; `git rev-parse origin/k3d-manager-v1.33.0` equals the commit SHA; report the SHA

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the listed targets
- Do NOT commit to `main`
- Do NOT edit `scripts/lib/foundation/` or `scripts/lib/system.sh` (subtree)
- Do NOT grant `secret/data/*` or any write capability to ESO
- Do NOT put any token, CA or password in argv, logs, git, or `--from-literal`
- Do NOT run anything against a live cluster, Vault, Keychain, launchd or Cloudflare
- Do NOT run `launchctl` in code paths — print the operator command instead

## Targets

- `scripts/plugins/argocd.sh`
- `scripts/plugins/vault.sh`
- `scripts/plugins/ldap.sh`
- `scripts/plugins/keycloak.sh`
- `scripts/plugins/hub_recovery.sh`
- `scripts/etc/cloudflared/origins.tsv` (new)
- `bin/cluster-up`
- `scripts/tests/plugins/hub_recovery.bats`, `scripts/tests/plugins/vault.bats` and `scripts/tests/plugins/argocd.bats`
- `CHANGELOG.md`
