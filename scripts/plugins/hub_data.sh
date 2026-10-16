#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2329,SC2030,SC2031

set -euo pipefail

K3DM_HUB_DATA_REPO="${K3DM_HUB_DATA_REPO:-git@github-k3dm-hub-data:wilddog64/k3dm-hub-data.git}"
K3DM_HUB_DATA_DIR="${K3DM_HUB_DATA_DIR:-${HOME}/.k3dm/hub-data}"
_HUB_DATA_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
K3DM_HUB_DATA_AGE_RECIPIENT="${K3DM_HUB_DATA_AGE_RECIPIENT:-${_HUB_DATA_ROOT}/scripts/etc/dr/age-recipient.txt}"
K3DM_HUB_DATA_CONTEXT="${K3DM_HUB_DATA_CONTEXT:-k3d-k3d-cluster}"
K3DM_HUB_DATA_RETAIN_DAYS="${K3DM_HUB_DATA_RETAIN_DAYS:-5}"
K3DM_HUB_DATA_PUSHGATEWAY_URL="${K3DM_HUB_DATA_PUSHGATEWAY_URL:-http://localhost:19094/metrics/job/k3dm-hub-data-export}"
K3DM_HUB_DATA_ARGOCD_PARENT="${K3DM_HUB_DATA_ARGOCD_PARENT:-shopping-cart-apps}"
K3DM_HUB_DATA_ARGOCD_APP="${K3DM_HUB_DATA_ARGOCD_APP:-shopping-cart-identity}"
K3DM_HUB_DATA_RECOVER_RUN_ROOT="${K3DM_HUB_DATA_RECOVER_RUN_ROOT:-${HOME}/.k3dm/hub-recover}"

if [[ -r "${PLUGINS_DIR}/hub_snapshot.sh" ]] && ! declare -f _hub_snapshot_copy >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${PLUGINS_DIR}/hub_snapshot.sh"
fi
if [[ -r "${PLUGINS_DIR}/hub_recovery.sh" ]] && ! declare -f _hub_recovery_restore_one >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${PLUGINS_DIR}/hub_recovery.sh"
fi

function _hub_data_claims() {
  printf '%s\n' 'secrets|data-vault-0' 'identity|postgres-keycloak-pvc' 'identity|data-openldap-0'
}

function _hub_data_stage() {
  local stage
  stage="$(mktemp -d "${TMPDIR:-/tmp}/k3dm-hub-data.XXXXXX")"
  chmod 700 "$stage"
  printf '%s\n' "$stage"
}

function _hub_data_latest_export_dir() {
  find "$1/snapshots" -mindepth 1 -maxdepth 1 -type d -name '20*T*Z' -print 2>/dev/null | sort -r | head -1
}

function _hub_data_encrypted_checksum() {
  local root="$1" file rel
  : > "${root}/SHA256SUMS"
  while IFS= read -r file; do
    rel="${file#"${root}"/}"
    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum "$file" | awk -v r="$rel" '{print $1 "  " r}' >> "${root}/SHA256SUMS"
    else
      shasum -a 256 "$file" | awk -v r="$rel" '{print $1 "  " r}' >> "${root}/SHA256SUMS"
    fi
  done < <(find "$root" -type f \( -name '*.age' -o -name '*.age.part-*' -o -name 'pv-pvc.yaml' -o -name 'inventory.json' \) -print | sort)
}

# Prints and returns instead of exiting (lib-foundation's _err exits), so the caller can add context
# (prune's "cannot verify kept export", the remote check's "did not verify").
function _hub_data_verify_fail() { printf 'ERROR: %s\n' "$*" >&2; return 1; }

function _hub_data_verify_export() {
  local dir="$1" stamp="${1##*/}" sum file rel actual key has_pv=0 has_inventory=0 legacy=0
  local -A manifest=() files=() age_seen=()
  [[ -s "$dir/SHA256SUMS" ]] || { _hub_data_verify_fail "[hub-data] export ${stamp} does not match its manifest: SHA256SUMS"; return 1; }
  while read -r sum rel; do
    [[ "$sum" =~ ^[[:xdigit:]]{64}$ && -n "$rel" ]] || { _hub_data_verify_fail "[hub-data] export ${stamp} does not match its manifest: ${rel:-invalid SHA256SUMS line}"; return 1; }
    [[ -z "${manifest[$rel]+x}" ]] || { _hub_data_verify_fail "[hub-data] export ${stamp} does not match its manifest: $rel"; return 1; }
    manifest["$rel"]="$sum"
    [[ "$rel" == pv-pvc.yaml ]] && has_pv=1
    [[ "$rel" == inventory.json ]] && has_inventory=1
    [[ -f "$dir/$rel" ]] || { _hub_data_verify_fail "[hub-data] export ${stamp} does not match its manifest: $rel"; return 1; }
    if command -v sha256sum >/dev/null 2>&1; then actual="$(sha256sum "$dir/$rel" | awk '{print $1}')"; else actual="$(shasum -a 256 "$dir/$rel" | awk '{print $1}')"; fi
    [[ "$actual" == "$sum" ]] || { _hub_data_verify_fail "[hub-data] export ${stamp} does not match its manifest: $rel"; return 1; }
  done < "$dir/SHA256SUMS"
  if (( has_pv == 0 && has_inventory == 0 )); then
    legacy=1
    _warn "[hub-data] export ${stamp} is a legacy export; pv-pvc.yaml and inventory.json are not covered by its manifest"
  elif (( has_pv != has_inventory )); then
    _hub_data_verify_fail "[hub-data] export ${stamp} does not match its manifest: pv-pvc.yaml and inventory.json must be listed together"
    return 1
  fi
  while IFS= read -r file; do
    rel="${file#"$dir"/}"
    files["$rel"]=1
  done < <(find "$dir" -type f ! -name SHA256SUMS -print)
  for rel in "${!manifest[@]}" "${!files[@]}"; do
    if (( legacy == 1 )) && [[ "$rel" == pv-pvc.yaml || "$rel" == inventory.json ]]; then continue; fi
    [[ -n "${manifest[$rel]+x}" && -n "${files[$rel]+x}" ]] || { _hub_data_verify_fail "[hub-data] export ${stamp} does not match its manifest: $rel"; return 1; }
  done
  while IFS= read -r file; do
    if [[ "$file" == *.age ]]; then
      key="$file"
    else
      key="${file%%.part-*}"
      [[ -z "${age_seen[$key]+x}" ]] || continue
      age_seen["$key"]=1
      file="$(find "$dir" -name "$(basename "$key").part-*" -print | sort | head -1)"
    fi
    if [[ "$(head -n 1 "$file")" != age-encryption.org/v1* ]]; then
      _hub_data_verify_fail "[hub-data] export ${stamp} does not match its manifest: ${file#"$dir"/} is not an age file"
      return 1
    fi
  done < <(find "$dir" -type f \( -name '*.age' -o -name '*.age.part-*' \) -print | sort)
}

function _hub_data_split_large() {
  local root="$1" file
  while IFS= read -r file; do
    if [[ "$(wc -c < "$file")" -ge 99614720 ]]; then
      split -b 90m "$file" "${file}.part-"
      rm -f "$file"
    fi
  done < <(find "$root" -type f -name '*.age' -size +94999k -print)
}

function _hub_data_yaml_metadata() {
  local root="$1" ns="$2" claim="$3" size storage modes node
  size="$(_kubectl -n "$ns" get pvc "$claim" -o json | jq -r '.spec.resources.requests.storage')"
  storage="$(_kubectl -n "$ns" get pvc "$claim" -o json | jq -r '.spec.storageClassName')"
  modes="$(_kubectl -n "$ns" get pvc "$claim" -o json | jq -r '.spec.accessModes[]')"
  node="$(_hub_snapshot_claim_node "$ns" "$claim")"
  node="$(_hub_recovery_logical_node "$node")"
  cat >> "${root}/pv-pvc.yaml" <<YAML
apiVersion: dr.k3d-manager/v1
kind: HubClaimMetadata
metadata:
  name: ${claim}
  namespace: ${ns}
spec:
  size: ${size}
  storageClass: ${storage}
  accessModes:
$(while IFS= read -r mode; do printf '    - %s\n' "$mode"; done <<<"$modes")
  logicalNode: ${node}
---
YAML
}

function _hub_data_vault_revoke() {
  local token="$1" ns="$2" release="$3"
  printf '%s\n' "$token" | _vault_exec_stream --no-exit "$ns" "$release" -- sh -lc 'read -r VAULT_TOKEN; export VAULT_TOKEN; exec vault token revoke -self' sh
}

function _hub_data_vault_kv_list() {
  local token="$1" ns="$2" release="$3" path="$4"
  [[ "$path" =~ ^[A-Za-z0-9_./-]+$ ]] || { _err "[hub-data] invalid Vault KV path: ${path}"; return 1; }
  printf '%s\n%s\n' "$token" "$path" | _vault_exec_stream --no-exit "$ns" "$release" -- sh -lc 'read -r VAULT_TOKEN; read -r KV_PATH; export VAULT_TOKEN; exec vault kv list -format=json "$KV_PATH"' sh
}

function _hub_data_vault_kv_metadata() {
  local token="$1" ns="$2" release="$3" path="$4"
  printf '%s\n%s\n' "$token" "$path" | _vault_exec_stream --no-exit "$ns" "$release" -- sh -lc 'read -r VAULT_TOKEN; read -r KV_PATH; export VAULT_TOKEN; exec vault kv metadata get -format=json "$KV_PATH"' sh
}

function _hub_data_kv_names() {
  jq -ce 'if type == "array" then . else .data end | select(type == "array" and length > 0 and all(.[]; type == "string"))' <<<"$1"
}

function _hub_data_generate_root() (
  local ns="$1" release="$2" otp nonce token encoded shard count idx output started=0 complete=0
  _hub_data_cancel_root() {
    (( started == 1 && complete == 0 )) || return 0
    _vault_exec_stream --no-exit "$ns" "$release" -- vault operator generate-root -cancel >/dev/null 2>&1 || true
  }
  trap _hub_data_cancel_root EXIT
  output="$(_vault_exec_stream --no-exit "$ns" "$release" -- vault operator generate-root -generate-otp -format=json)"
  otp="$(jq -r '.otp // empty' <<<"$output")"
  [[ -n "$otp" ]] || return 1
  output="$(printf '%s\n' "$otp" | _vault_exec_stream --no-exit "$ns" "$release" -- sh -lc 'read -r OTP; vault operator generate-root -init -otp="$OTP" -format=json')"
  nonce="$(jq -r '.nonce // empty' <<<"$output")"
  [[ -n "$nonce" ]] || return 1
  started=1
  count="$(_secret_load_data k3dm-vault-unseal-dr "${ns}/${release}:count" vault-unseal-dr)"
  for ((idx=1; idx<=count; idx++)); do
    shard="$(_secret_load_data k3dm-vault-unseal-dr "${ns}/${release}:shard${idx}" vault-unseal-dr)"
    output="$(printf '%s\n%s\n' "$nonce" "$shard" | _vault_exec_stream --no-exit "$ns" "$release" -- sh -lc 'read -r NONCE; read -r SHARD; printf "%s\\n" "$SHARD" | vault operator generate-root -nonce "$NONCE" -format=json -')"
    encoded="$(jq -r '.encoded_token // empty' <<<"$output")"
  done
  [[ -n "$encoded" ]] || return 1
  token="$(printf '%s\n%s\n' "$encoded" "$otp" | _vault_exec_stream --no-exit "$ns" "$release" -- sh -lc 'read -r ENCODED; read -r OTP; printf "%s\\n" "$ENCODED" | vault operator generate-root -decode=- -otp="$OTP"')"
  [[ -n "$token" ]] || return 1
  complete=1
  printf '%s\n' "$token"
)

function _hub_data_inventory_token() {
  local ns="$1" release="$2" jwt token
  jwt="$(_no_trace _kubectl -n secrets create token hub-data-export --duration=10m)" || return 1
  token="$(printf '%s\n' "$jwt" | _no_trace _vault_exec_stream --no-exit --stdin --pod "${release}-0" "$ns" "$release" -- vault write -field=token auth/kubernetes/login role=hub-data-inventory jwt=-)" || true
  if [[ -z "$token" ]]; then
    _err "[hub-data] Vault login as hub-data-export failed; run make hub-data-export-setup"
    return 1
  fi
  printf '%s\n' "$token"
}

# Both counts run with the pod's own credentials: the hub's Postgres role is $POSTGRES_USER, not
# postgres, and OpenLDAP refuses anonymous binds, so LDAP is read over ldapi as the server's own uid.
function _hub_data_keycloak_user_count() {
  local realm="${KEYCLOAK_REALM:-shopping-cart}"
  [[ "$realm" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
  "$@" -n identity exec deployment/postgres-keycloak -- sh -c "psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -Atc \"SELECT count(*) FROM user_entity WHERE realm_id=(SELECT id FROM realm WHERE name='${realm}');\"" 2>/dev/null | tr -d '[:space:]'
}

function _hub_data_ldap_entry_count() {
  "$@" -n identity exec statefulset/openldap -- sh -c 'ldapsearch -Q -Y EXTERNAL -H ldapi:/// -LLL -b "$LDAP_ROOT" dn' 2>/dev/null | awk '/^dn:/{n++} END{print n+0}'
}

function _hub_data_keycloak_user_digest() {
  local realm="${KEYCLOAK_REALM:-shopping-cart}"
  "$@" -n identity exec deployment/postgres-keycloak -- sh -c "psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -Atc \"SELECT username FROM user_entity WHERE realm_id=(SELECT id FROM realm WHERE name='${realm}') ORDER BY username;\"" 2>/dev/null | shasum -a 256 | awk '{print $1}'
}

function _hub_data_ldap_dn_digest() {
  "$@" -n identity exec statefulset/openldap -- sh -c 'ldapsearch -Q -Y EXTERNAL -H ldapi:/// -LLL -b "$LDAP_ROOT" dn' 2>/dev/null | awk '/^dn:/{print $2}' | sort | shasum -a 256 | awk '{print $1}'
}

function _hub_data_inventory_images() {
  local context
  context="$(_hub_data_target_context)"
  jq -n \
    --arg vault "$(_kubectl --context "$context" -n secrets get pod vault-0 -o jsonpath='{.spec.containers[0].image}')" \
    --arg keycloak "$(_kubectl --context "$context" -n identity get pod -l app.kubernetes.io/name=postgres-keycloak -o jsonpath='{.items[0].spec.containers[0].image}')" \
    --arg ldap "$(_kubectl --context "$context" -n identity get pod openldap-0 -o jsonpath='{.spec.containers[0].image}')" \
    '{"secrets/vault-0":$vault,"identity/postgres-keycloak":$keycloak,"identity/openldap-0":$ldap}'
}

function _hub_data_inventory_vault_keys() {
  local token="$1" ns="$2" release="$3" path listing child metadata key version
  local -a pending=("secret/")
  declare -A seen=() result=()
  while ((${#pending[@]})); do
    path="${pending[0]}"; pending=("${pending[@]:1}")
    [[ -n "${seen[$path]+x}" ]] && continue
    seen["$path"]=1
    listing="$(_hub_data_vault_kv_list "$token" "$ns" "$release" "$path")" || { _err "[hub-data] vault kv list ${path} failed; run make hub-data-export-setup"; return 1; }
    while IFS= read -r child; do
      [[ -n "$child" ]] || continue
      if [[ "$child" == */ ]]; then
        pending+=("${path}${child}")
      else
        key="${path#secret/}${child}"
        metadata="$(_hub_data_vault_kv_metadata "$token" "$ns" "$release" "secret/${key}")" || { _err "[hub-data] vault kv metadata get secret/${key} failed"; return 1; }
        version="$(jq -r '.data.current_version // .data.metadata.current_version // empty' <<<"$metadata")"
        [[ "$version" =~ ^[1-9][0-9]*$ ]] || { _err "[hub-data] secret/${key} has no current version"; return 1; }
        result["$key"]="$version"
      fi
    done < <(_hub_data_kv_names "$listing" | jq -r '.[]')
  done
  local json='{}'
  for key in "${!result[@]}"; do
    json="$(jq --arg k "$key" --arg v "${result[$key]}" '. + {($k):{current_version:($v|tonumber)}}' <<<"$json")"
  done
  printf '%s\n' "$json"
}

function _hub_data_inventory() (
  local root="$1" ns="${VAULT_NS:-secrets}" release="${VAULT_RELEASE:-vault}" token paths users ldap images keycloak_digest ldap_digest vault_keys cleanup=0
  _hub_data_revoke_root() { (( cleanup == 1 )) || return 0; _hub_data_vault_revoke "$token" "$ns" "$release" >/dev/null 2>&1 || true; }
  trap _hub_data_revoke_root EXIT
  token="$(_hub_data_inventory_token "$ns" "$release")" && [[ -n "$token" ]] || return 1
  cleanup=1
  paths="$(_hub_data_vault_kv_list "$token" "$ns" "$release" secret/)" || { _err "[hub-data] vault kv list secret/ failed"; return 1; }
  paths="$(_hub_data_kv_names "$paths")" || { _err "[hub-data] vault kv list secret/ returned no paths"; return 1; }
  users="$(_hub_data_keycloak_user_count _kubectl)"
  ldap="$(_hub_data_ldap_entry_count _kubectl)"
  [[ "$users" =~ ^[1-9][0-9]*$ ]] || { _err "[hub-data] Keycloak user count is not a positive number: '${users}'"; return 1; }
  [[ "$ldap" =~ ^[1-9][0-9]*$ ]] || { _err "[hub-data] LDAP entry count is not a positive number: '${ldap}'"; return 1; }
  images="$(_hub_data_inventory_images)" || { _err "[hub-data] could not read the vault, postgres-keycloak and openldap images"; return 1; }
  keycloak_digest="$(_hub_data_keycloak_user_digest _kubectl)" || { _err "[hub-data] could not digest the Keycloak usernames"; return 1; }
  ldap_digest="$(_hub_data_ldap_dn_digest _kubectl)" || { _err "[hub-data] could not digest the LDAP DNs"; return 1; }
  vault_keys="$(_hub_data_inventory_vault_keys "$token" "$ns" "$release")" || return 1
  jq -n --argjson p "$paths" --argjson u "$users" --argjson l "$ldap" --argjson i "$images" --arg kd "$keycloak_digest" --arg ld "$ldap_digest" --argjson vk "$vault_keys" \
    '{format:2,images:$i,vault_paths:$p,keycloak_realm_user_count:$u,ldap_entry_count:$l,keycloak_usernames_sha256:$kd,ldap_dns_sha256:$ld,vault_keys:$vk}' > "${root}/inventory.json"
  _hub_data_vault_revoke "$token" "$ns" "$release" >/dev/null 2>&1; cleanup=0
)

function hub_data_export_setup() { (
  local ns="${VAULT_NS:-secrets}" release="${VAULT_RELEASE:-vault}" policy='path "secret/metadata/" { capabilities = ["list"] }
path "secret/metadata/*" { capabilities = ["read", "list"] }' stage token listing cleanup=0
  stage="$(_hub_data_stage)"; trap 'rm -rf -- "$stage"' EXIT
  _hub_data_pin_context "$stage"
  _vault_login "$ns" "$release"
  _kubectl -n secrets create sa hub-data-export --dry-run=client -o yaml | _kubectl apply -f -
  printf '%s\n' "$policy" | _no_trace _vault_exec_stream --no-exit --stdin --pod "${release}-0" "$ns" "$release" -- vault policy write hub-data-inventory -
  local audience="${K8S_TOKEN_AUDIENCE:-https://kubernetes.default.svc.cluster.local}"
  [[ "$audience" =~ ^[A-Za-z0-9:/._-]+$ ]] || { _err "[hub-data] invalid K8S_TOKEN_AUDIENCE: ${audience}"; return 1; }
  _vault_exec "$ns" "vault write auth/kubernetes/role/hub-data-inventory bound_service_account_names=hub-data-export bound_service_account_namespaces=secrets policies=hub-data-inventory ttl=5m audience=${audience}" "$release"
  # The self-test must run as the unattended export does. _vault_login's admin session would be
  # injected on stdin ahead of the list call's own token and path, so drop it first.
  unset "_VAULT_SESSION_TOKENS[${ns}/${release}]"
  token="$(_hub_data_inventory_token "$ns" "$release")" || return 1
  cleanup=1
  _hub_data_revoke_setup_token() { (( cleanup == 1 )) || return 0; _hub_data_vault_revoke "$token" "$ns" "$release" >/dev/null 2>&1 || true; }
  trap '_hub_data_revoke_setup_token; rm -rf -- "$stage"' EXIT
  listing="$(_hub_data_vault_kv_list "$token" "$ns" "$release" secret/)" || { _err "[hub-data] Vault inventory self-test: vault kv list secret/ failed as hub-data-export"; return 1; }
  _hub_data_kv_names "$listing" >/dev/null || { _err "[hub-data] Vault inventory self-test returned no paths"; return 1; }
  _hub_data_inventory_vault_keys "$token" "$ns" "$release" >/dev/null || { _err "[hub-data] Vault inventory self-test: the metadata walk under secret/ failed as hub-data-export"; return 1; }
  _hub_data_vault_revoke "$token" "$ns" "$release" >/dev/null 2>&1; cleanup=0
) }

function _hub_data_pin_context() {
  local stage="$1" context kubeconfig
  context="${K3DM_HUB_DATA_CONTEXT}"; kubeconfig="${stage}/kubeconfig"
  if ! _kubectl config view --minify --flatten --context "$context" > "$kubeconfig" 2>/dev/null || [[ ! -s "$kubeconfig" ]]; then
    _err "[hub-data] hub context ${context} not found"
    return 1
  fi
  chmod 600 "$kubeconfig"
  export KUBECONFIG="$kubeconfig"
}

# The lock records its owner's PID, so a run killed mid-export (a shutdown at 03:30) does not block
# every later run: a lock whose owner is gone is taken over.
function _hub_data_take_lock() {
  local lock="${K3DM_HUB_DATA_DIR}/export.lock" owner
  mkdir -p "$K3DM_HUB_DATA_DIR"
  if ! mkdir "$lock" 2>/dev/null; then
    owner="$(cat "$lock/pid" 2>/dev/null || true)"
    if [[ "$owner" =~ ^[0-9]+$ ]] && kill -0 "$owner" 2>/dev/null; then
      _info "[hub-data] another export is running"
      return 1
    fi
    _warn "[hub-data] removing stale export lock (owner ${owner:-unknown} is not running)"
    rm -rf -- "$lock"
    mkdir "$lock" 2>/dev/null || { _info "[hub-data] another export is running"; return 1; }
  fi
  printf '%s\n' "$BASHPID" > "$lock/pid"
}

function _hub_data_release_lock() {
  local lock="${K3DM_HUB_DATA_DIR}/export.lock"
  [[ "$(cat "$lock/pid" 2>/dev/null || true)" == "$BASHPID" ]] && rm -rf -- "$lock"
  return 0
}

function _hub_data_remote_verify() (
  local repo="$1" stamp="$2" pushed_sha remote_sha verify_stage verify_repo
  verify_stage="$(_hub_data_stage)"
  trap 'rm -rf -- "$verify_stage"' EXIT
  pushed_sha="$(git -C "$repo" rev-parse HEAD)"
  remote_sha="$(git -C "$repo" ls-remote origin refs/heads/snapshots | awk '{print $1}')"
  if [[ "$remote_sha" != "$pushed_sha" ]]; then
    _err "[hub-data] export ${stamp} pushed but the remote copy did not verify: ls-remote mismatch"
    return 1
  fi
  verify_repo="${verify_stage}/repo"
  if ! git clone --depth 1 --filter=blob:none --no-checkout --branch snapshots "$K3DM_HUB_DATA_REPO" "$verify_repo" >/dev/null; then
    _err "[hub-data] export ${stamp} pushed but the remote copy did not verify: clone failed"
    return 1
  fi
  if ! git -C "$verify_repo" checkout "$pushed_sha" -- "snapshots/${stamp}" >/dev/null; then
    _err "[hub-data] export ${stamp} pushed but the remote copy did not verify: checkout failed"
    return 1
  fi
  if ! _hub_data_verify_export "$verify_repo/snapshots/${stamp}"; then
    _err "[hub-data] export ${stamp} pushed but the remote copy did not verify: manifest"
    return 1
  fi
)

function _hub_data_export_bytes() { find "$1" -type f -exec wc -c {} + | awk '{sum += $1} END {print sum+0}'; }

function _hub_data_export_timestamp_epoch() {
  local stamp="$1" iso parsed
  if parsed="$(TZ=UTC date -j -f '%Y%m%dT%H%M%SZ' "$stamp" +%s 2>/dev/null)"; then
    printf '%s\n' "$parsed"
    return 0
  fi
  if [[ "$stamp" =~ ^([0-9]{8})T([0-9]{6})Z$ ]]; then
    iso="${BASH_REMATCH[1]:0:4}-${BASH_REMATCH[1]:4:2}-${BASH_REMATCH[1]:6:2} ${BASH_REMATCH[2]:0:2}:${BASH_REMATCH[2]:2:2}:${BASH_REMATCH[2]:4:2}"
    if parsed="$(TZ=UTC date -u -d "$iso" +%s 2>/dev/null)"; then
      printf '%s\n' "$parsed"
      return 0
    fi
  fi
  return 1
}

function _hub_data_push_metrics() (
  local success="$1" bytes="$2" kept="$3" now body
  now="$(date +%s)"
  body="$(mktemp "${TMPDIR:-/tmp}/k3dm-hub-data-metrics.XXXXXX")"
  trap 'rm -f -- "$body"' EXIT
  printf 'k3dm_hub_data_export_last_run_timestamp_seconds %s\nk3dm_hub_data_export_last_run_success %s\n' "$now" "$success" > "$body"
  if (( success == 1 )); then
    printf 'k3dm_hub_data_export_last_success_timestamp_seconds %s\nk3dm_hub_data_export_exports_kept %s\nk3dm_hub_data_export_bytes %s\n' "$now" "$kept" "$bytes" >> "$body"
  fi
  if ! curl --fail -X POST --data-binary "@${body}" "$K3DM_HUB_DATA_PUSHGATEWAY_URL" >/dev/null; then
    _warn "[hub-data] metrics push failed"
  fi
)

function hub_data_export() { (
  [[ -r "$K3DM_HUB_DATA_AGE_RECIPIENT" ]] || { _err "[hub-data] missing age recipient: $K3DM_HUB_DATA_AGE_RECIPIENT"; return 1; }
  local stage repo root stamp ns claim logical path container export_rc bytes kept
  if [[ "${HUB_DATA_LOCK_HELD:-0}" != 1 ]]; then
    _hub_data_take_lock || return 1
  fi
  stage="$(_hub_data_stage)"
  if [[ "${HUB_DATA_LOCK_HELD:-0}" == 1 ]]; then
    trap 'rm -rf -- "$stage"' EXIT
  else
    trap 'rm -rf -- "$stage"; _hub_data_release_lock' EXIT
  fi
  _hub_data_pin_context "$stage" || return 1
  repo="${stage}/repo"; git clone --branch snapshots "$K3DM_HUB_DATA_REPO" "$repo"; chmod 700 "$repo"
  stamp="${K3DM_HUB_DATA_TIMESTAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"; root="${repo}/snapshots/${stamp}"
  mkdir -p "$root"; : > "${root}/pv-pvc.yaml"
  while IFS='|' read -r ns claim; do
    logical="$(_hub_snapshot_claim_node "$ns" "$claim")"; logical="$(_hub_recovery_logical_node "$logical")"
    path="$(_hub_snapshot_claim_path "$(_hub_snapshot_claim_pv "$ns" "$claim")")"
    container="$(_hub_snapshot_node_container "$logical")"
    docker exec "$container" tar -C "$path" -cf - . | age -r "$(tr -d '\n' < "$K3DM_HUB_DATA_AGE_RECIPIENT")" -o "${root}/${ns}-${claim}.tar.age"
    _hub_data_yaml_metadata "$root" "$ns" "$claim"
  done < <(_hub_data_claims)
  if ! _hub_data_inventory "$root"; then _err "[hub-data] could not record the inventory (Vault paths, Keycloak users, LDAP entries); nothing was pushed"; return 1; fi
  _hub_data_split_large "$root"; _hub_data_encrypted_checksum "$root"
  _hub_data_verify_export "$root" || return 1
  (cd "$repo" && git add snapshots && git commit -m "snapshot: ${stamp}" && git push origin snapshots) || return 1
  _hub_data_remote_verify "$repo" "$stamp" || return 1
  if ! hub_data_prune "$repo"; then
    _err "[hub-data] export ${stamp} pushed; prune failed"
    return 1
  fi
  export_rc=0
  bytes="$(_hub_data_export_bytes "$root")"
  kept=0
  [[ -r "${K3DM_HUB_DATA_DIR}/last-kept" ]] && kept="$(<"${K3DM_HUB_DATA_DIR}/last-kept")"
  printf '%s\n' "$stamp" > "${K3DM_HUB_DATA_DIR}/last-success"
  printf '%s\n' "$bytes" > "${K3DM_HUB_DATA_DIR}/last-bytes"
  return "$export_rc"
) }

function hub_data_prune() { (
  local stage repo results_ref now cutoff newest result_file passing keep_csv="" dir stamp age tree new old_sha repo_arg result_files
  local -a keep=() prune=()
  repo_arg="${1:-}"
  if [[ -n "$repo_arg" ]]; then
    repo="$repo_arg"
  else
    stage="$(_hub_data_stage)"; trap 'rm -rf -- "$stage"' EXIT
    repo="${stage}/repo"; git clone --branch snapshots "$K3DM_HUB_DATA_REPO" "$repo" >/dev/null || return 1
  fi
  if ! git -C "$repo" fetch origin '+refs/heads/results:refs/remotes/origin/results' >/dev/null 2>&1; then
    _err "[hub-data] cannot read drill results; nothing pruned"; return 1
  fi
  results_ref="refs/remotes/origin/results"
  result_files="$(git -C "$repo" ls-tree -r --name-only "$results_ref" | grep -E '^results/[0-9]{8}T[0-9]{6}Z\.json$' | sort -r || true)"
  result_file=""
  while IFS= read -r dir; do
    if git -C "$repo" show "${results_ref}:${dir}" 2>/dev/null | jq -e '.success == true and (.export | type == "string")' >/dev/null 2>&1; then result_file="$dir"; break; fi
  done <<< "$result_files"
  if [[ -z "$result_file" ]]; then
    if [[ -z "$result_files" ]]; then
      _err "[hub-data] cannot read drill results; nothing pruned"; return 1
    fi
    passing=""
  else
    passing="$(git -C "$repo" show "${results_ref}:${result_file}" | jq -er '.export')"
  fi
  now="$(date -u +%s)"; cutoff=$((now - K3DM_HUB_DATA_RETAIN_DAYS * 86400))
  newest="$(find "$repo/snapshots" -mindepth 1 -maxdepth 1 -type d -name '20*T*Z' -print | sort -r | head -1)"
  [[ -n "$newest" ]] || return 0
  while IFS= read -r dir; do
    stamp="${dir##*/}"
    if ! age="$(_hub_data_export_timestamp_epoch "$stamp")"; then
      _err "[hub-data] cannot parse export timestamp ${stamp}; nothing pruned"
      return 1
    fi
    if (( age >= cutoff )) || [[ "$dir" == "$newest" ]] || [[ "$stamp" == "$passing" ]]; then keep+=("$stamp"); else prune+=("$stamp"); fi
  done < <(find "$repo/snapshots" -mindepth 1 -maxdepth 1 -type d -name '20*T*Z' -print | sort)
  for stamp in "${keep[@]}"; do
    _hub_data_verify_export "$repo/snapshots/$stamp" || { _err "[hub-data] cannot verify kept export ${stamp}; nothing pruned"; return 1; }
  done
  keep_csv="$(IFS=,; printf '%s' "${keep[*]}")"
  K3DM_HUB_DATA_EXPORTS_KEPT="${#keep[@]}"
  export K3DM_HUB_DATA_EXPORTS_KEPT
  for stamp in "${keep[@]}"; do printf 'keep: %s\n' "$stamp"; done
  for stamp in "${prune[@]}"; do printf 'prune: %s\n' "$stamp"; done
  [[ "${K3DM_HUB_DATA_PRUNE_DRY_RUN:-0}" == 1 ]] && return 0
  mkdir -p "$K3DM_HUB_DATA_DIR"
  printf '%s\n' "$K3DM_HUB_DATA_EXPORTS_KEPT" > "$K3DM_HUB_DATA_DIR/last-kept"
  (( ${#prune[@]} )) || return 0
  old_sha="$(git -C "$repo" rev-parse refs/remotes/origin/snapshots 2>/dev/null || git -C "$repo" rev-parse HEAD)"
  git -C "$repo" rm -r -q --cached "${prune[@]/#/snapshots/}" || return 1
  tree="$(git -C "$repo" write-tree)"; new="$(cd "$repo" && git commit-tree "$tree" -m "prune: keep ${keep_csv}")"
  git -C "$repo" push --force-with-lease="snapshots:${old_sha}" origin "${new}:refs/heads/snapshots"
) }

function hub_data_export_scheduled() { (
  local rc=0 bytes kept
  _hub_data_take_lock || return 0
  trap '_hub_data_release_lock' EXIT
  export GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=15'
  HUB_DATA_LOCK_HELD=1 hub_data_export || rc=$?
  bytes=0; kept=0
  [[ -r "$K3DM_HUB_DATA_DIR/last-bytes" ]] && bytes="$(<"$K3DM_HUB_DATA_DIR/last-bytes")"
  [[ -r "$K3DM_HUB_DATA_DIR/last-kept" ]] && kept="$(<"$K3DM_HUB_DATA_DIR/last-kept")"
  if (( rc == 0 )); then _hub_data_push_metrics 1 "$bytes" "$kept"; else _hub_data_push_metrics 0 0 0; fi
  return "$rc"
) }

function hub_data_export_schedule() { (
  local template="${SCRIPT_DIR}/etc/launchd/com.k3d-manager.hub-data-export.plist.tmpl" plist="${HOME}/Library/LaunchAgents/com.k3d-manager.hub-data-export.plist"
  _is_mac || return 0; command -v launchctl >/dev/null 2>&1 || { _warn "[hub-data] launchctl not available"; return 0; }
  mkdir -p "$(dirname "$plist")"
  sed -e "s|{{K3D_MANAGER_PATH}}|${SCRIPT_DIR}/k3d-manager|g" -e "s|{{HOME}}|${HOME}|g" "$template" > "$plist"
  launchctl bootout "gui/$(id -u)/com.k3d-manager.hub-data-export" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$plist"
) }

function hub_data_export_unschedule() { (
  _is_mac || return 0
  launchctl bootout "gui/$(id -u)/com.k3d-manager.hub-data-export" 2>/dev/null || true
) }

function _hub_data_meta_field() {
  local file="$1" ns="$2" claim="$3" field="$4"
  awk -v ns="$ns" -v claim="$claim" -v field="$field" '$0 == "  name: " claim {hit=1} hit && $0 == "  namespace: " ns {matched=1} matched && $0 ~ "^  " field ":" {sub("^  " field ": *", ""); print; exit} /^---$/ {hit=0; matched=0}' "$file"
}

function _hub_data_meta_modes() {
  local file="$1" ns="$2" claim="$3"
  awk -v ns="$ns" -v claim="$claim" '$0 == "  name: " claim {hit=1} hit && $0 == "  namespace: " ns {matched=1} matched && /^    - / {sub(/^    - /, ""); print} /^---$/ {hit=0; matched=0}' "$file"
}

function _hub_data_workload() {
  case "$1/$2" in
    secrets/data-vault-0) printf '%s\n' statefulset/vault ;;
    identity/postgres-keycloak-pvc) printf '%s\n' deployment/postgres-keycloak ;;
    identity/data-openldap-0) printf '%s\n' statefulset/openldap ;;
    *) return 1 ;;
  esac
}

function _hub_data_scale() {
  local ns="$1" claim="$2" replicas="$3" workload
  workload="$(_hub_data_workload "$ns" "$claim")" || { _err "[hub-data] unknown workload for ${ns}/${claim}"; return 1; }
  local context
  context="$(_hub_data_target_context)"
  if ! _kubectl --context "$context" -n "$ns" scale "$workload" --replicas="$replicas"; then
    _err "[hub-data] unable to scale ${workload}"
    return 1
  fi
}

function _hub_data_apply_keycloak() {
  local manifest="${K3DM_HUB_DATA_POSTGRES_MANIFEST:-${_HUB_DATA_ROOT}/scripts/etc/dr/postgres-keycloak.yaml}"
  [[ -f "$manifest" ]] || { _err "[hub-data] missing ${manifest}"; return 1; }
  _kubectl --context "$(_hub_data_target_context)" -n identity apply -f "$manifest"
}

function _hub_data_target_context() {
  if [[ "${DR_DRILL_MODE:-0}" == 1 ]]; then
    printf '%s\n' "${DR_DRILL_CONTEXT:-}"
  else
    printf '%s\n' "${K3DM_HUB_DATA_CONTEXT:-}"
  fi
}

function _hub_data_wait_vault() {
  local prefix="${1:-[dr-drill]}" limit="${DR_DRILL_VAULT_START_S:-300}" deadline phase="" rc=0
  deadline=$((SECONDS + limit))
  while (( SECONDS < deadline )); do
    phase="$(_kubectl --no-exit -n secrets get pod vault-0 -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    [[ "$phase" == Running ]] && break
    sleep "${DR_DRILL_POLL_S:-5}"
  done
  if [[ "$phase" != Running ]]; then
    printf '%s vault-0 is not Running after %ss (phase: %s)\n' "$prefix" "$limit" "${phase:-none}" >&2
    return 1
  fi
  VAULT_API_WAIT_S="$limit" _vault_wait_api secrets vault || rc=$?
  (( rc == 0 )) || printf '%s the restored Vault API did not answer within %ss\n' "$prefix" "$limit" >&2
  return "$rc"
}

function hub_data_unseal_dr() {
  local prefix="${1:-[dr-drill]}" count shard idx out
  _hub_data_wait_vault "$prefix" || return 1
  if ! count="$(_secret_load_data k3dm-vault-unseal-dr 'secrets/vault:count' vault-unseal-dr)"; then
    printf '%s no DR shard count in Keychain service k3dm-vault-unseal-dr (account secrets/vault:count) on this Mac, or it is empty; repeat the shard import\n' "$prefix" >&2
    return 1
  fi
  if [[ ! "$count" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s the DR shard count in Keychain (secrets/vault:count) is not a positive number; repeat the shard import\n' "$prefix" >&2
    return 1
  fi
  for ((idx=1; idx<=count; idx++)); do
    if ! shard="$(_secret_load_data k3dm-vault-unseal-dr "secrets/vault:shard${idx}" vault-unseal-dr)"; then
      printf '%s DR shard %s of %s is missing or empty in Keychain; repeat the shard import\n' "$prefix" "$idx" "$count" >&2
      return 1
    fi
    shard="${shard%$'\r'}"
    if ! _vault_dr_shard_valid "$shard"; then
      printf '%s DR shard %s of %s in Keychain is not a base64 or hex unseal key; repeat the shard copy from the M4\n' "$prefix" "$idx" "$count" >&2
      return 1
    fi
    if ! out="$(printf '%s\n' "$shard" | _vault_exec_stream --no-exit --stdin --pod vault-0 secrets vault -- sh -lc 'read -r SHARD; printf "%s" "$SHARD" | vault write -format=json sys/unseal key=-' 2>&1)"; then
      printf '%s vault operator unseal failed for shard %s of %s\n' "$prefix" "$idx" "$count" >&2
      grep -F -v -- "$shard" <<<"$out" | grep -E 'Error|error|Code:|^\* ' | head -5 | sed "s/^/${prefix}   /" >&2 || true
      return 1
    fi
  done
}

function _hub_data_restore_one() {
  local ns="$1" claim="$2" encrypted node path identity source_dir source_name cluster="${DR_DRILL_CLUSTER:-${K3DM_HUB_DATA_CLUSTER:-k3d-cluster}}"
  encrypted="$3"; node="$4"; path="$5"; identity="${K3DM_HUB_DATA_AGE_IDENTITY:-}"; source_dir="${encrypted%/*}"; source_name="${encrypted##*/}"
  if [[ -z "$identity" ]]; then
    if [[ "${HUB_DATA_RESTORE_TARGET:-drill}" == hub ]]; then
      _err '[hub-data] no age identity in memory; hub mode never reads it from the Keychain'
      return 1
    fi
    identity="$(_secret_load_data k3dm-hub-data-age identity age)"
  fi
  if [[ "${DR_DRILL_MODE:-0}" == 1 && "${HUB_DATA_RESTORE_TARGET:-drill}" != hub && "k3d-${cluster}-${node}" != k3d-dr-drill-* ]]; then
    _err '[hub-data] refusing: target is not the drill cluster (docker restore target)'
    return 2
  fi
  if [[ -f "$encrypted" ]]; then
    age -d -i <(printf '%s\n' "$identity") "$encrypted" | docker exec -i "k3d-${cluster}-${node}" tar -C "$path" -xpf -
  else
    find "$source_dir" -name "${source_name}.part-*" -print | sort | xargs cat | age -d -i <(printf '%s\n' "$identity") - | docker exec -i "k3d-${cluster}-${node}" tar -C "$path" -xpf -
  fi
}

function _hub_data_prepare_claim() {
  local stage="$1" ns="$2" claim="$3" encrypted="$4" node pv path actual logical storage size modes
  node="$(_hub_data_meta_field "${stage}/pv-pvc.yaml" "$ns" "$claim" logicalNode)"; storage="$(_hub_data_meta_field "${stage}/pv-pvc.yaml" "$ns" "$claim" storageClass)"
  size="$(_hub_data_meta_field "${stage}/pv-pvc.yaml" "$ns" "$claim" size)"; modes="$(_hub_data_meta_modes "${stage}/pv-pvc.yaml" "$ns" "$claim")"
  [[ -n "$node" && -n "$size" && -n "$storage" && -n "$modes" ]] || return 1
  _hub_data_scale "$ns" "$claim" 0 >/dev/null || return 1
  local context cluster="${DR_DRILL_CLUSTER:-${K3DM_HUB_DATA_CLUSTER:-k3d-cluster}}"
  context="$(_hub_data_target_context)"
  _kubectl --context "$context" -n "$ns" delete pvc "$claim" --ignore-not-found >/dev/null
  { printf 'apiVersion: v1\nkind: PersistentVolumeClaim\nmetadata:\n  name: %s\n  namespace: %s\n  annotations:\n    volume.kubernetes.io/selected-node: k3d-%s-%s\nspec:\n  storageClassName: %s\n  accessModes:\n' "$claim" "$ns" "$cluster" "$node" "$storage"; _hub_data_meta_modes "${stage}/pv-pvc.yaml" "$ns" "$claim" | sed 's/^/    - /'; printf '  resources:\n    requests:\n      storage: %s\n' "$size"; } | _kubectl --context "$context" apply --server-side --field-manager=k3dm-hub-restore -f -
  _kubectl --context "$context" -n "$ns" wait --for=jsonpath='{.status.phase}'=Bound "pvc/${claim}" --timeout=300s
  pv="$(_kubectl --context "$context" -n "$ns" get pvc "$claim" -o jsonpath='{.spec.volumeName}')"
  actual="$(_kubectl --context "$context" get pv "$pv" -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[?(@.key=="kubernetes.io/hostname")].values[0]}')"; logical="$(_hub_recovery_logical_node "$actual")"
  [[ "$logical" == "$node" ]] || { _err "[hub-data] PV node mismatch for ${ns}/${claim}"; return 1; }
  path="$(_kubectl --context "$context" get pv "$pv" -o jsonpath='{.spec.local.path}')"
  printf '%s\t%s\t%s\t%s\n' "$ns" "$claim" "$node" "$path" >> "${stage}/restore-targets.tsv"
}

function _hub_data_copy_claim() {
  local stage="$1" ns="$2" claim="$3" encrypted="$4" node path
  IFS=$'\t' read -r _ _ node path < <(awk -v n="$ns" -v c="$claim" '$1 == n && $2 == c {print}' "${stage}/restore-targets.tsv")
  [[ -n "$node" && -n "$path" ]] || return 1
  _hub_data_restore_one "$ns" "$claim" "$encrypted" "$node" "$path"
}

function hub_data_restore() { (
  local stage repo latest ns claim created=0 target="${HUB_DATA_RESTORE_TARGET:-drill}"
  if [[ "$target" != hub && ( -z "${DR_DRILL_CONTEXT:-}" || -z "${DR_DRILL_CLUSTER:-}" ) ]]; then
    printf 'ERROR: %s\n' "[hub-data] DR_DRILL_CONTEXT and DR_DRILL_CLUSTER are required" >&2
    return 2
  fi
  if [[ -n "${DR_DRILL_RESTORE_STAGE:-}" ]]; then
    stage="$DR_DRILL_RESTORE_STAGE"
  else
    stage="$(_hub_data_stage)"
    created=1
  fi
  mkdir -p "$stage"; chmod 700 "$stage"
  if (( created == 1 )); then trap 'rm -rf -- "$stage"' EXIT; fi
  : > "${stage}/restore-targets.tsv"
  if [[ -n "${HUB_DATA_RESTORE_EXPORT_DIR:-}" ]]; then
    latest="$HUB_DATA_RESTORE_EXPORT_DIR"
  else
    repo="${stage}/repo"
    git clone --depth 1 --branch snapshots "$K3DM_HUB_DATA_REPO" "$repo"
    chmod 700 "$repo"
    latest="$(_hub_data_latest_export_dir "$repo")"
  fi
  [[ -n "$latest" ]] || return 1
  _hub_data_verify_export "$latest" || return 1
  cp "$latest/pv-pvc.yaml" "$stage/pv-pvc.yaml"
  cp "$latest/inventory.json" "$stage/inventory.json"
  if [[ "$target" == hub ]]; then
    _kubectl --context "${K3DM_HUB_DATA_CONTEXT}" -n identity get deployment/postgres-keycloak >/dev/null || { _err '[hub-data] deployment/postgres-keycloak is required in hub mode'; return 1; }
  else
    _hub_data_apply_keycloak || return 1
  fi
  while IFS='|' read -r ns claim; do
    if ! _hub_data_prepare_claim "$stage" "$ns" "$claim" "${latest}/${ns}-${claim}.tar.age"; then return 1; fi
  done < <(_hub_data_claims)
  while IFS='|' read -r ns claim; do
    _hub_data_copy_claim "$stage" "$ns" "$claim" "${latest}/${ns}-${claim}.tar.age" || return 1
  done < <(_hub_data_claims)
  while IFS='|' read -r ns claim; do
    if ! _hub_data_scale "$ns" "$claim" 1; then return 1; fi
  done < <(_hub_data_claims)
) }

function hub_data_verify_vault_paths() { (
  local ns="${1:-secrets}" release="${2:-vault}" inventory="${3:?inventory path required}" token cleanup=0 path want restored
  local -a paths=()
  _hub_data_revoke_root() { (( cleanup == 1 )) || return 0; _hub_data_vault_revoke "$token" "$ns" "$release" >/dev/null 2>&1 || true; }
  trap _hub_data_revoke_root EXIT
  want="$(jq -ce '.vault_paths' "$inventory" 2>/dev/null)" && want="$(_hub_data_kv_names "$want")" || { _err "[hub-data] the inventory records no Vault paths; nothing to verify"; return 1; }
  while IFS= read -r path; do
    [[ "$path" =~ ^[A-Za-z0-9_./-]+$ ]] || { _err "[hub-data] invalid Vault KV path: ${path}"; return 1; }
    paths+=("$path")
  done < <(jq -r '.[]' <<<"$want")
  token="$(_hub_data_generate_root "$ns" "$release")" && [[ -n "$token" ]] || { _err "[hub-data] could not generate a Vault root token from the DR shards"; return 1; }
  cleanup=1
  restored="$(_hub_data_vault_kv_list "$token" "$ns" "$release" secret/)" || { _err "[hub-data] vault kv list secret/ failed"; return 1; }
  restored="$(_hub_data_kv_names "$restored")" || { _err "[hub-data] vault kv list secret/ returned no paths"; return 1; }
  for path in "${paths[@]}"; do
    jq -e --arg p "$path" 'any(.[]; . == $p)' <<<"$restored" >/dev/null || { _err "[hub-data] Vault path missing after restore: secret/${path}"; return 1; }
  done
  if jq -e 'has("vault_keys")' "$inventory" >/dev/null 2>&1; then
    local key expected_version actual_version metadata
    while IFS=$'\t' read -r key expected_version; do
      metadata="$(_hub_data_vault_kv_metadata "$token" "$ns" "$release" "secret/${key}")" || { _err "[hub-data] Vault metadata missing: secret/${key}"; return 1; }
      actual_version="$(jq -r '.data.current_version // .data.metadata.current_version // empty' <<<"$metadata")"
      [[ "$actual_version" == "$expected_version" ]] || { _err "[hub-data] Vault current_version mismatch: secret/${key}"; return 1; }
    done < <(jq -r '.vault_keys | to_entries[] | [.key,.value.current_version // .value] | @tsv' "$inventory")
  fi
  _hub_data_vault_revoke "$token" "$ns" "$release" >/dev/null 2>&1; cleanup=0
) }

function _hub_data_argocd_pause() {
  local context="$1" parent="${K3DM_HUB_DATA_ARGOCD_PARENT}" app="${K3DM_HUB_DATA_ARGOCD_APP}" ns="${ARGOCD_NAMESPACE:-cicd}" dir="$2" value current
  mkdir -p "$dir"
  for value in "$parent" "$app"; do
    if _kubectl --no-exit --context "$context" -n "$ns" get application "$value" >/dev/null 2>&1; then
      current="$(_kubectl --no-exit --context "$context" -n "$ns" get application "$value" -o jsonpath='{.spec.syncPolicy.automated}')" || return 1
      if [[ ( -n "$current" && "$current" != null ) || ! -e "$dir/$value.automated" ]]; then
        printf '%s' "$current" > "$dir/$value.automated"
      fi
      _kubectl --context "$context" -n "$ns" patch application "$value" --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}' >/dev/null
    elif [[ "$value" == "$app" ]]; then
      _info "[hub-recover] ${value} not found; skipping ArgoCD child"
    else
      _info "[hub-recover] ${value} not found; pausing only the child"
    fi
  done
  for value in "$parent" "$app"; do
    if [[ -s "$dir/$value.automated" ]] && ! _hub_data_argocd_assert_paused "$context" "$dir"; then
      _err "[hub-recover] ArgoCD ${value} auto-sync was restored during pause"
      return 1
    fi
  done
}

function _hub_data_argocd_assert_paused() {
  local context="$1" dir="$2" ns="${ARGOCD_NAMESPACE:-cicd}" value current
  for value in "$K3DM_HUB_DATA_ARGOCD_PARENT" "$K3DM_HUB_DATA_ARGOCD_APP"; do
    [[ -r "$dir/$value.automated" ]] || continue
    current="$(_kubectl --no-exit --context "$context" -n "$ns" get application "$value" -o jsonpath='{.spec.syncPolicy.automated}')" || return 1
    [[ -z "$current" || "$current" == null ]] || return 1
  done
}

function _hub_data_argocd_resume() {
  local context="$1" dir="$2" ns="${ARGOCD_NAMESPACE:-cicd}" value payload error
  for value in "$K3DM_HUB_DATA_ARGOCD_APP" "$K3DM_HUB_DATA_ARGOCD_PARENT"; do
    [[ -r "$dir/$value.automated" ]] || continue
    payload="$(<"$dir/$value.automated")"
    [[ -n "$payload" && "$payload" != null ]] || continue
    if ! _kubectl --context "$context" -n "$ns" patch application "$value" --type merge -p "{\"spec\":{\"syncPolicy\":{\"automated\":${payload}}}}" >/dev/null; then
      error="$( ( _err "[hub-recover] failed to resume ${value}" ) 2>&1 || true )"
      printf '%s\n' "$error" >&2
      printf '%s\n' false > "$dir/argocd_resume"
    fi
  done
}

function _hub_data_checkpoint() {
  local file="$1" step="$2" state="$3" now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ "$state" == start ]]; then
    printf '{"step":%s,"started":"%s"}\n' "$step" "$now" >> "$file"
  else
    printf '{"step":%s,"finished":"%s","rc":%s}\n' "$step" "$now" "$state" >> "$file"
  fi
}

function _hub_data_step_finished() {
  [[ -s "$2" ]] || return 1
  jq -se --argjson step "$1" 'any(.[]; .step == $step and .finished != null and .rc == 0)' "$2" >/dev/null 2>&1
}

function _hub_data_step_unfinished() {
  [[ -s "$2" ]] || return 1
  jq -se --argjson step "$1" 'any(.[]; .step == $step and .started != null) and (any(.[]; .step == $step and .finished != null and .rc == 0) | not)' "$2" >/dev/null 2>&1
}

function _hub_data_refresh_dependents() {
  local context="$1"
  if [[ "$context" == k3d-dr-drill || "${K3DM_HUB_DATA_RECOVER_ALLOW_DRILL:-0}" == 1 ]]; then
    printf '%s\n' '[hub-recover] drill target: no Keycloak or ESO to refresh; skipping' >&2
    return 0
  fi
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
}

function _hub_data_record_rto() {
  local run_dir="$1" fallback="$2" approval_epoch
  approval_epoch="$(cat "$run_dir/approval_epoch" 2>/dev/null || true)"
  if [[ "$approval_epoch" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$(( $(date +%s) - approval_epoch ))" > "$run_dir/rto_seconds"
  else
    printf '%s\n' "$fallback" > "$run_dir/rto_seconds"
  fi
}

function _hub_data_run_step() {
  local file="$1" step="$2"; shift 2; local step_rc
  _hub_data_checkpoint "$file" "$step" start
  set +e; "$@"; step_rc=$?; set -e
  _hub_data_checkpoint "$file" "$step" "$step_rc"
  return "$step_rc"
}

function _hub_data_repoint_vault() {
  local context="$1" dir="${2:-}" root_token count idx shard ns="secrets" release="vault"
  root_token="$(_hub_data_generate_root "$ns" "$release")" || return 1
  _no_trace _vault_exec_stream --no-exit --stdin --pod vault-0 "$ns" "$release" -- sh -lc 'read -r VAULT_TOKEN; export VAULT_TOKEN; vault write auth/kubernetes/config token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" kubernetes_host="https://kubernetes.default.svc:443" kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt' <<<"$root_token" || return 1
  count="$(_secret_load_data k3dm-vault-unseal-dr 'secrets/vault:count' vault-unseal-dr)" || return 1
  [[ "$count" =~ ^[1-9][0-9]*$ ]] || return 1
  local -a shards=()
  for ((idx=1; idx<=count; idx++)); do
    shard="$(_secret_load_data k3dm-vault-unseal-dr "secrets/vault:shard${idx}" vault-unseal-dr)" || return 1
    shard="${shard%$'\r'}"
    [[ -n "$shard" ]] && _vault_dr_shard_valid "$shard" || return 1
    shards+=("$shard")
  done
  if [[ "$context" == k3d-dr-drill || "${K3DM_HUB_DATA_RECOVER_ALLOW_DRILL:-0}" == 1 ]]; then
    printf '%s\n' '[hub-recover] drill target: not caching unseal keys in the Keychain (it holds this host'"'"'s own cluster keys)' >&2
    [[ -z "$dir" ]] || printf '%s\n' skipped > "$dir/unseal_keys_cache"
  else
    _vault_cache_unseal_keys "$ns" "$release" "${shards[@]}" || return 1
    [[ -z "$dir" ]] || printf '%s\n' cached > "$dir/unseal_keys_cache"
  fi
  printf '%s' "$root_token" | jq -Rs '{apiVersion:"v1",kind:"Secret",metadata:{name:"vault-root",namespace:"secrets"},type:"Opaque",stringData:{root_token:.}}' | _kubectl --context "$context" apply -f - || return 1
  _hub_recovery_sync_vault_root_token "$context" || return 1
}

function _hub_data_recover_approval() {
  local export_ts="$1" typed
  [[ -t 0 || "${K3DM_HUB_DATA_TEST_TTY:-0}" == 1 ]] || { printf '%s\n' '[hub-recover] interactive TTY required' >&2; return 2; }
  printf '[hub-recover] Type export timestamp %s to approve: ' "$export_ts" >&2
  IFS= read -r typed < "${K3DM_HUB_DATA_TTY_DEVICE:-/dev/tty}" || return 2
  [[ "$typed" == "$export_ts" ]] || { printf '%s\n' '[hub-recover] approval did not match the selected export' >&2; return 2; }
}

function _hub_data_validate_target() {
  local context="$1" cluster="$2" server port containers
  server="$(_kubectl --context "$context" config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null)" || return 2
  port="${server##*:}"; [[ "$port" =~ ^[0-9]+$ ]] || { _err '[hub-recover] context server has no port'; return 2; }
  containers="$(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null)" || { _err '[hub-recover] cannot inspect local k3d containers'; return 2; }
  grep -Eq "^k3d-${cluster}-serverlb[[:space:]].*:${port}->6443" <<<"$containers" || { _err '[hub-recover] context server is not the local serverlb'; return 2; }
  grep -Eq "^k3d-${cluster}-server-0([[:space:]]|$)" <<<"$containers" || { _err '[hub-recover] local server-0 is not running'; return 2; }
  local pair ns workload
  for pair in 'secrets statefulset/vault' 'identity deployment/postgres-keycloak' 'identity statefulset/openldap'; do
    read -r ns workload <<<"$pair"
    _kubectl --context "$context" -n "$ns" get "$workload" >/dev/null || { _err "[hub-recover] missing workload $workload"; return 2; }
  done
}

function _hub_data_install_credential_guard() {
  local run_dir="$1" context="$2"
  _HUB_DATA_SECURITY_SHIM="${_HUB_DATA_ROOT}/scripts/etc/dr/security-shim"
  export DR_SECURITY_CREDENTIALS_FILE="${run_dir}/credentials.tsv"
  export DR_SECURITY_UNEXPECTED_FILE="${run_dir}/credentials_unexpected.tsv"
  export DR_SECURITY_ALLOWLIST="${_HUB_DATA_ROOT}/scripts/etc/dr/credential-allowlist.tsv"
  export DR_SECURITY_CONTEXT="$context"
  if [[ "$context" == k3d-dr-drill || "${K3DM_HUB_DATA_RECOVER_ALLOW_DRILL:-0}" == 1 ]]; then
    export DR_SECURITY_SCOPES="restore restore-drill"
  else
    export DR_SECURITY_SCOPES="restore restore-hub"
  fi
  touch "$DR_SECURITY_CREDENTIALS_FILE" "$DR_SECURITY_UNEXPECTED_FILE"
  local shim_dir="${run_dir}/bin"
  mkdir -p "$shim_dir"
  ln -sf "$_HUB_DATA_SECURITY_SHIM" "${shim_dir}/security"
  export PATH="${shim_dir}:$PATH"
  security() { "$_HUB_DATA_SECURITY_SHIM" "$@"; }
}

function _hub_data_check_compatibility() {
  local dir="$1" inventory format context target_images key export_image target_image
  inventory="$dir/inventory.json"
  format="$(jq -r '.format // 0' "$inventory" 2>/dev/null || printf 0)"
  if [[ "$format" != 2 && "${K3DM_HUB_DATA_ALLOW_LEGACY_EXPORT:-0}" != 1 ]]; then
    _err '[hub-recover] export inventory format 2 is required (set K3DM_HUB_DATA_ALLOW_LEGACY_EXPORT=1 only for a rehearsal)'
    return 1
  fi
  for claim in data-vault-0 postgres-keycloak-pvc data-openldap-0; do
    grep -q "name: $claim" "$dir/pv-pvc.yaml" || { _err "[hub-recover] export is missing claim $claim"; return 1; }
  done
  if [[ "$format" == 2 ]]; then
    context="$(_hub_data_target_context)"
    target_images="$(_hub_data_inventory_images)" || return 1
    while IFS=$'\t' read -r key export_image; do
      target_image="$(jq -r --arg k "$key" '.[$k] // empty' <<<"$target_images")"
      local export_major target_major
      export_major="$(sed -n 's/.*:\([0-9][0-9]*\)\..*/\1/p' <<<"${export_image%%@*}")"
      target_major="$(sed -n 's/.*:\([0-9][0-9]*\)\..*/\1/p' <<<"${target_image%%@*}")"
      if [[ -n "$export_major" && -n "$target_major" && "$export_major" != "$target_major" ]]; then
        _err "[hub-recover] image major mismatch for ${key}: export ${export_image}, target ${target_image}"
        return 1
      fi
    done < <(jq -r '.images | to_entries[] | [.key,.value] | @tsv' "$inventory")
  fi
}

function _hub_data_report() {
  local run_dir="$1" rc="$2" report steps_json checks_json target_json export_dir export_ts sums_digest approval_time
  report="$run_dir/report.json"
  steps_json='[]'; [[ -s "$run_dir/steps.jsonl" ]] && steps_json="$(jq -s 'group_by(.step) | map({step:.[0].step,started:(map(select(.started != null))[0].started // null),finished:(map(select(.finished != null))[-1].finished // null),rc:(map(select(.finished != null))[-1].rc // null)})' "$run_dir/steps.jsonl")"
  checks_json='{}'; [[ -s "$run_dir/checks.json" ]] && checks_json="$(<"$run_dir/checks.json")"
  target_json='{}'; [[ -s "$run_dir/target.json" ]] && target_json="$(<"$run_dir/target.json")"
  export_dir="${K3DM_HUB_DATA_EXPORT_DIR:-}"; export_ts="${export_dir##*/}"
  sums_digest=''; [[ -n "$export_dir" && -r "$export_dir/SHA256SUMS" ]] && sums_digest="$(shasum -a 256 "$export_dir/SHA256SUMS" | awk '{print $1}')"
  approval_time=''; [[ -r "$run_dir/approval_time" ]] && approval_time="$(<"$run_dir/approval_time")"
  local credentials='[]' unexpected='[]'
  [[ -s "$run_dir/credentials.tsv" ]] && credentials="$(jq -R -s 'split("\n") | map(select(length > 0) | split("\t") | {op:.[0],service:.[1],account:.[2]}) | unique' "$run_dir/credentials.tsv")"
  [[ -s "$run_dir/credentials_unexpected.tsv" ]] && unexpected="$(jq -R -s 'split("\n") | map(select(length > 0) | split("\t") | {op:.[0],service:.[1],account:.[2]}) | unique' "$run_dir/credentials_unexpected.tsv")"
  jq -n --arg run "$(basename "$run_dir")" --arg host "$(hostname)" --arg operator "$(id -un)" --arg commit "$(git rev-parse HEAD 2>/dev/null || true)" --arg export "$export_ts" --arg sums "$sums_digest" --arg approval "$approval_time" --argjson target "$target_json" --argjson steps "$steps_json" --argjson checks "$checks_json" --argjson rc "$rc" --arg resume "$(cat "$run_dir/argocd_resume" 2>/dev/null || printf true)" --argjson rto "$(cat "$run_dir/rto_seconds" 2>/dev/null || printf 0)" --arg keycache "$(cat "$run_dir/unseal_keys_cache" 2>/dev/null || printf none)" --argjson credentials "$credentials" --argjson unexpected "$unexpected" \
    '{run_id:$run,host:$host,operator:$operator,commit:$commit,target:$target,export_timestamp:$export,sha256sums:$sums,approval_time:$approval,steps:$steps,checks:$checks,argocd_resume:($resume=="true"),unseal_keys_cache:$keycache,rto_seconds:$rto,rc:$rc,credentials_read:$credentials,credentials_unexpected:$unexpected}' > "$report"
}

function hub_data_verify_unsealed() {
  local context="$1" stage old_kubeconfig had_kubeconfig=0 rc=0
  stage="$(_hub_data_stage)"
  old_kubeconfig="${KUBECONFIG:-}"
  [[ -n "${KUBECONFIG+x}" ]] && had_kubeconfig=1
  if [[ -n "${DR_DRILL_CONTEXT:-}" && "$DR_DRILL_CONTEXT" == "$context" && -n "${KUBECONFIG:-}" ]]; then
    :
  else
    K3DM_HUB_DATA_CONTEXT="$context" _hub_data_pin_context "$stage" || { rm -rf -- "$stage"; return 1; }
  fi
  _vault_exec secrets 'vault status -format=json' vault | jq -e '.sealed == false' >/dev/null || rc=$?
  if (( had_kubeconfig == 1 )); then export KUBECONFIG="$old_kubeconfig"; else unset KUBECONFIG; fi
  rm -rf -- "$stage"
  return "$rc"
}
function hub_data_verify_keycloak() {
  local inventory="$1" context="$2" want actual expected digest
  want="$(jq -r '.keycloak_realm_user_count' "$inventory")"; actual="$(_hub_data_keycloak_user_count _kubectl --context "$context")"; [[ "$actual" == "$want" ]] || return 1
  if jq -e 'has("keycloak_usernames_sha256")' "$inventory" >/dev/null 2>&1; then
    expected="$(jq -r '.keycloak_usernames_sha256' "$inventory")"; digest="$(_hub_data_keycloak_user_digest _kubectl --context "$context")"
    [[ "$expected" == "$digest" ]] || { _err '[hub-data] Keycloak usernames digest mismatch'; return 1; }
  fi
}
function hub_data_verify_ldap() {
  local inventory="$1" context="$2" want actual expected digest
  want="$(jq -r '.ldap_entry_count' "$inventory")"; actual="$(_hub_data_ldap_entry_count _kubectl --context "$context")"; [[ "$actual" == "$want" ]] || return 1
  if jq -e 'has("ldap_dns_sha256")' "$inventory" >/dev/null 2>&1; then
    expected="$(jq -r '.ldap_dns_sha256' "$inventory")"; digest="$(_hub_data_ldap_dn_digest _kubectl --context "$context")"
    [[ "$expected" == "$digest" ]] || { _err '[hub-data] LDAP DN digest mismatch'; return 1; }
  fi
}
function hub_data_verify_placement() {
  local inventory="$1" context="$2" postgres expected actual logical metadata="${DR_DRILL_METADATA:-}"
  [[ -n "$metadata" || -z "${DR_DRILL_RESTORE_STAGE:-}" ]] || metadata="${DR_DRILL_RESTORE_STAGE}/pv-pvc.yaml"
  [[ -n "$metadata" || -z "${K3DM_HUB_DATA_EXPORT_DIR:-}" ]] || metadata="${K3DM_HUB_DATA_EXPORT_DIR}/pv-pvc.yaml"
  [[ -r "$metadata" ]] || { printf '%s\n' "[hub-data] V5: no readable pv-pvc.yaml (set by the drill stage or K3DM_HUB_DATA_EXPORT_DIR): '${metadata}'" >&2; return 1; }
  postgres="$(_kubectl --context "$context" -n identity get pods -l app.kubernetes.io/name=postgres-keycloak -o jsonpath='{.items[0].metadata.name}')"; [[ -n "$postgres" ]] || return 1
  while IFS=$'\t' read -r ns pod claim; do
    _kubectl --context "$context" -n "$ns" wait --for=condition=Ready "pod/${pod}" --timeout=300s >/dev/null || return 1
    expected="$(_hub_data_meta_field "$metadata" "$ns" "$claim" logicalNode)"; actual="$(_kubectl --context "$context" -n "$ns" get pod "$pod" -o jsonpath='{.spec.nodeName}')"; logical="$(_hub_recovery_logical_node "$actual")"; [[ "$logical" == "$expected" ]] || return 1
  done <<EOF
secrets	vault-0	data-vault-0
identity	${postgres}	postgres-keycloak-pvc
identity	openldap-0	data-openldap-0
EOF
}
function hub_data_verify_externalsecrets() {
  local context="$1" deadline=$((SECONDS + ${K3DM_HUB_DATA_V8_WAIT_S:-300})) json
  while (( SECONDS <= deadline )); do
    json="$(_kubectl --context "$context" get externalsecret --all-namespaces -o json)" || return 1
    [[ -z "$json" ]] && return 0
    ! jq -e '[.items[]?.status.conditions[]? | select(.type == "Ready" and .reason == "SecretSyncedError")] | length > 0' <<<"$json" >/dev/null && return 0
    sleep "${K3DM_HUB_DATA_V8_POLL_S:-5}"
  done
  return 1
}
function hub_data_verify() {
  local inventory="${1:?inventory path required}" ns="${2:-identity}" context="${3:-${K3DM_HUB_DATA_CONTEXT:-k3d-k3d-cluster}}" name rc all=true
  local -a names=(V1 V2 V3 V4 V5 V8)
  local -a funcs=(hub_data_verify_unsealed hub_data_verify_vault_paths hub_data_verify_keycloak hub_data_verify_ldap hub_data_verify_placement hub_data_verify_externalsecrets)
  printf '{}' > "${HUB_DATA_VERIFY_REPORT:-/tmp/k3dm-hub-checks.json}"
  for ((i=0; i<${#names[@]}; i++)); do
    name="${names[$i]}"
    set +e
    if [[ "$name" == V1 ]]; then
      "${funcs[$i]}" "$context"
    elif [[ "$name" == V2 ]]; then
      "${funcs[$i]}" secrets vault "$inventory"
    elif [[ "$name" == V8 ]]; then
      "${funcs[$i]}" "$context"
    else
      "${funcs[$i]}" "$inventory" "$context"
    fi
    rc=$?
    set -e
    (( rc == 0 )) || all=false
    printf '%s\t%s\n' "$name" "$([[ $rc -eq 0 ]] && printf true || printf false)"
    jq --arg n "$name" --argjson v "$([[ $rc -eq 0 ]] && printf true || printf false)" '. + {($n):$v}' "${HUB_DATA_VERIFY_REPORT:-/tmp/k3dm-hub-checks.json}" > "${HUB_DATA_VERIFY_REPORT:-/tmp/k3dm-hub-checks.json}.tmp" && mv "${HUB_DATA_VERIFY_REPORT:-/tmp/k3dm-hub-checks.json}.tmp" "${HUB_DATA_VERIFY_REPORT:-/tmp/k3dm-hub-checks.json}"
  done
  [[ "$all" == true ]]
}

function hub_data_recover_preflight() {
  local context="${K3DM_HUB_DATA_CONTEXT:-k3d-k3d-cluster}" cluster="${K3DM_HUB_DATA_CLUSTER:-k3d-cluster}" repo export_dir export_ts run_id run_dir
  local server='' nodes='' live_users='' live_ldap='' export_users export_ldap export_paths
  run_id="$(date -u +%Y%m%dT%H%M%SZ)"
  run_dir="${K3DM_HUB_DATA_RECOVER_RUN_ROOT}/${run_id}"
  mkdir -p "$run_dir"
  repo="${run_dir}/repo"
  git clone --depth 1 --branch snapshots "$K3DM_HUB_DATA_REPO" "$repo"
  chmod 700 "$repo"
  export_dir="${K3DM_HUB_DATA_EXPORT:-}"
  if [[ -n "$export_dir" ]]; then
    export_dir="$repo/snapshots/$export_dir"
  else
    export_dir="$(_hub_data_latest_export_dir "$repo")"
  fi
  [[ -d "$export_dir" ]] || return 1
  _hub_data_verify_export "$export_dir" || return 1
  _hub_data_check_compatibility "$export_dir" || return 1
  export_ts="${export_dir##*/}"
  export_users="$(jq -r '.keycloak_realm_user_count' "$export_dir/inventory.json")"
  export_ldap="$(jq -r '.ldap_entry_count' "$export_dir/inventory.json")"
  export_paths="$(jq -r '.vault_paths | length' "$export_dir/inventory.json")"
  local present_rc=0
  _hub_data_cluster_exists "$cluster" || present_rc=$?
  if [[ "$present_rc" -gt 1 ]]; then
    _err "[hub-recover] cannot list k3d clusters; refusing to guess whether '${cluster}' exists"
  fi
  if [[ "$present_rc" -eq 0 ]]; then
    printf '%s\n' 1 > "${run_dir}/hub_present"
    _hub_data_validate_target "$context" "$cluster" || return 2
    server="$(_kubectl --context "$context" config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
    nodes="$(_kubectl --context "$context" get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}')"
    live_users="$(_hub_data_keycloak_user_count _kubectl --context "$context" 2>/dev/null || printf 'n/a')"
    live_ldap="$(_hub_data_ldap_entry_count _kubectl --context "$context" 2>/dev/null || printf 'n/a')"
    printf '[hub-recover] Target context: %s\n[hub-recover] Server URL: %s\n[hub-recover] Nodes: %s\n[hub-recover] Export: %s\n[hub-recover] Counts (Vault paths, Keycloak users, LDAP entries): live n/a (needs Vault login)/%s/%s; export %s/%s/%s\n' "$context" "$server" "$nodes" "$export_ts" "$live_users" "$live_ldap" "$export_paths" "$export_users" "$export_ldap" >&2
    printf "[hub-recover] This DELETES the local hub '%s' and rebuilds it, then restores export %s.\n" "$cluster" "$export_ts" >&2
  else
    printf '%s\n' 0 > "${run_dir}/hub_present"
    printf "[hub-recover] No local hub '%s': it will be built from scratch, then export %s restored.\n" "$cluster" "$export_ts" >&2
  fi
  mkdir -p "$K3DM_HUB_DATA_RECOVER_RUN_ROOT"
  jq -n --arg context "$context" --arg server "$server" --arg cluster "$cluster" --arg nodes "$nodes" '{context:$context,server_url:$server,cluster:$cluster,nodes:($nodes|split(" ")|map(select(length>0)))}' > "${run_dir}/target.json"
  _hub_data_recover_approval "$export_ts" || return 2
  printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${run_dir}/approval_time"
  date +%s > "${run_dir}/approval_epoch"
  printf '%s\n' "$export_dir" > "${run_dir}/export_dir"
  printf 'RUN_ID=%s\n' "$run_id"
}

function _hub_data_cluster_down() {
  local cluster="$1"
  CLUSTER_PROVIDER=k3d HUB_CLUSTER_NAME="$cluster" "${_HUB_DATA_ROOT}/bin/cluster-down" --confirm --delete-hub
}

function _hub_data_cluster_exists() {
  local cluster="$1" listing
  listing="$(k3d cluster list 2>/dev/null)" || return 2
  grep -q "^${cluster}[[:space:]]" <<<"$listing"
}

function hub_data_recover_teardown() {
  local run_id="${1:?run id required}" cluster="${K3DM_HUB_DATA_CLUSTER:-k3d-cluster}" hub_present containers network volume
  local run_dir="${K3DM_HUB_DATA_RECOVER_RUN_ROOT}/${run_id}" networks volumes
  [[ -r "${run_dir}/hub_present" ]] || { _err "[hub-recover] missing hub_present for run ${run_id}"; return 1; }
  hub_present="$(cat "${run_dir}/hub_present")"
  [[ "$hub_present" == 0 || "$hub_present" == 1 ]] || { _err "[hub-recover] invalid hub_present for run ${run_id}"; return 1; }
  if [[ "$hub_present" == 0 ]]; then
    printf '%s\n' '[hub-recover] no hub to delete'
  else
    _hub_data_cluster_down "$cluster" || return $?
  fi
  local exists_rc=0
  _hub_data_cluster_exists "$cluster" || exists_rc=$?
  if [[ "$exists_rc" -ne 1 ]]; then
    _err "[hub-recover] cluster ${cluster} still exists or cannot be listed after teardown"
    return 1
  fi
  containers="$(docker ps -a --filter "label=k3d.cluster=${cluster}" --format '{{.Names}}')"
  while IFS= read -r container; do
    [[ -n "$container" ]] || continue
    docker rm -f -- "$container"
  done <<<"$containers"
  network="k3d-${cluster}"
  networks="$(docker network ls --format '{{.Name}}')"
  if grep -Fxq "$network" <<<"$networks"; then
    docker network rm -- "$network"
  fi
  volume="k3d-${cluster}-images"
  volumes="$(docker volume ls --format '{{.Name}}')"
  if grep -Fxq "$volume" <<<"$volumes"; then
    docker volume rm -- "$volume"
  fi
  containers="$(docker ps -a --filter "label=k3d.cluster=${cluster}" --format '{{.Names}}')"
  [[ -z "$containers" ]] || { _err "[hub-recover] leftover containers for ${cluster}: ${containers}"; return 1; }
}

function _hub_data_recover_step2() {
  local steps="$1"
  printf '[hub-recover] Step 2/9 — age identity\n'
  K3DM_HUB_DATA_AGE_IDENTITY=""
  if [[ "${K3DM_HUB_DATA_AGE_IDENTITY_FROM_KEYCHAIN:-0}" == 1 ]]; then
    if [[ "${K3DM_HUB_DATA_RECOVER_ALLOW_DRILL:-0}" != 1 ]]; then
      printf '%s\n' '[hub-recover] K3DM_HUB_DATA_AGE_IDENTITY_FROM_KEYCHAIN is for drill rehearsals only; a real recovery types the key' >&2
      return 1
    fi
    K3DM_HUB_DATA_AGE_IDENTITY="$(_secret_load_data k3dm-hub-data-age identity age)"
    K3DM_HUB_DATA_AGE_IDENTITY="${K3DM_HUB_DATA_AGE_IDENTITY%$'\r'}"
    printf '%s\n' '[hub-recover] drill rehearsal: age identity loaded from the Keychain (k3dm-hub-data-age)' >&2
  elif ! read -rs -p '[hub-recover] Age identity: ' K3DM_HUB_DATA_AGE_IDENTITY < "${K3DM_HUB_DATA_TTY_DEVICE:-/dev/tty}"; then
    printf '%s\n' '[hub-recover] could not read the age identity from the TTY' >&2
    return 1
  fi
  printf '\n' >&2
  if [[ "$K3DM_HUB_DATA_AGE_IDENTITY" != AGE-SECRET-KEY-1* ]]; then
    printf '%s\n' '[hub-recover] the age identity must start with AGE-SECRET-KEY-1' >&2
    return 1
  fi
  _hub_data_run_step "$steps" 2 true
}
function _hub_data_recover_step3() {
  local steps="$1" context="$2" dir="$3"
  printf '[hub-recover] Step 3/9 — Pause ArgoCD\n'
  _hub_data_run_step "$steps" 3 _hub_data_argocd_pause "$context" "$dir"
}
function _hub_data_recover_step4() {
  local steps="$1" context="$2" dir="$3"
  _hub_data_step_finished 4 "$steps" && return 0
  if _hub_data_step_unfinished 4 "$steps" && [[ "${REDO_STEP:-}" != 4 ]]; then
    printf '%s\n' '[hub-recover] step 4 started but did not finish; set REDO_STEP=4 to repeat it' >&2
    return 1
  fi
  printf '[hub-recover] Step 4/9 — Restore claims\n'
  _hub_data_argocd_assert_paused "$context" "$dir" || return 1
  _hub_data_run_step "$steps" 4 hub_data_restore
}
function _hub_data_recover_step5() {
  local steps="$1"
  _hub_data_step_finished 5 "$steps" && return 0
  printf '[hub-recover] Step 5/9 — Unseal\n'
  _hub_data_run_step "$steps" 5 hub_data_unseal_dr '[hub-recover]'
}
function _hub_data_recover_step6() {
  local steps="$1" context="$2" dir="$3"
  _hub_data_step_finished 6 "$steps" && return 0
  if _hub_data_step_unfinished 6 "$steps" && [[ "${REDO_STEP:-}" != 6 ]]; then
    printf '%s\n' '[hub-recover] step 6 started but did not finish; set REDO_STEP=6 to repeat it' >&2
    return 1
  fi
  printf '[hub-recover] Step 6/9 — Re-point Vault\n'
  _hub_data_argocd_assert_paused "$context" "$dir" || return 1
  _hub_data_run_step "$steps" 6 _hub_data_repoint_vault "$context" "$dir"
}
function _hub_data_recover_step7() {
  local steps="$1" context="$2"
  _hub_data_step_finished 7 "$steps" && return 0
  printf '[hub-recover] Step 7/9 — Refresh dependents\n'
  _hub_data_run_step "$steps" 7 _hub_data_refresh_dependents "$context"
}
function _hub_data_recover_step8() {
  local steps="$1" context="$2" dir="$3"
  _hub_data_step_finished 8 "$steps" && return 0
  printf '[hub-recover] Step 8/9 — Verify\n'
  export HUB_DATA_VERIFY_REPORT="$dir/checks.json"
  _hub_data_run_step "$steps" 8 hub_data_verify "$dir/inventory.json" identity "$context"
}
function _hub_data_recover_step9() {
  local steps="$1"
  _hub_data_step_finished 9 "$steps" && return 0
  printf '[hub-recover] Step 9/9 — Report\n'
  printf '%s\n' '[hub-recover] next: make hub-data-export-setup && make hub-data-export (the rebuilt hub has no hub-data-export ServiceAccount until setup runs)'
  _hub_data_run_step "$steps" 9 true
}

function hub_data_recover() { (
  local context="${K3DM_HUB_DATA_CONTEXT:-k3d-k3d-cluster}" cluster="${K3DM_HUB_DATA_CLUSTER:-k3d-cluster}" export_dir export_ts run_id run_dir steps rc=0 preflight_output
  if [[ -n "${RESUME:-}" ]]; then
    run_id="$RESUME"
  else
    preflight_output="$(hub_data_recover_preflight)" || return $?
    run_id="${preflight_output##*RUN_ID=}"
  fi
  run_dir="${K3DM_HUB_DATA_RECOVER_RUN_ROOT}/${run_id}"
  mkdir -p "$run_dir"
  steps="$run_dir/steps.jsonl"
  _hub_data_install_credential_guard "$run_dir" "$context"
  trap 'rc=$?; set +e; _hub_data_argocd_resume "$context" "$run_dir"; _hub_data_report "$run_dir" "$rc"; unset K3DM_HUB_DATA_AGE_IDENTITY; exit "$rc"' EXIT
  printf '[hub-recover] Step 1/9 — Preflight\n'; [[ "$context" == k3d-dr-drill && "${K3DM_HUB_DATA_RECOVER_ALLOW_DRILL:-0}" != 1 ]] && return 2
  export_dir="$(cat "$run_dir/export_dir" 2>/dev/null || true)"
  [[ -d "$export_dir" ]] || return 1
  export_ts="${export_dir##*/}"
  export K3DM_HUB_DATA_EXPORT_DIR="$export_dir" HUB_DATA_RESTORE_EXPORT_DIR="$export_dir"
  cp "$export_dir/inventory.json" "$run_dir/inventory.json"
  _hub_data_verify_export "$export_dir" || return 1; _hub_data_check_compatibility "$export_dir" || return 1; _hub_data_validate_target "$context" "$cluster" || return 2; if [[ ! -r "$run_dir/approval_time" ]]; then _hub_data_recover_approval "$export_ts" || return 2; printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$run_dir/approval_time"; date +%s > "$run_dir/approval_epoch"; fi
  _hub_data_step_finished 1 "$steps" || _hub_data_run_step "$steps" 1 true || return $?
  _hub_data_recover_step2 "$steps" || return $?
  _hub_data_recover_step3 "$steps" "$context" "$run_dir" || return $?
  export K3DM_HUB_DATA_CONTEXT="$context" K3DM_HUB_DATA_CLUSTER="$cluster" HUB_DATA_RESTORE_TARGET=hub
  _hub_data_recover_step4 "$steps" "$context" "$run_dir" || return $?
  _hub_data_recover_step5 "$steps" || return $?
  _hub_data_recover_step6 "$steps" "$context" "$run_dir" || return $?
  _hub_data_recover_step7 "$steps" "$context" || return $?
  _hub_data_recover_step8 "$steps" "$context" "$run_dir" || return $?
  _hub_data_recover_step9 "$steps" || return $?
  _hub_data_record_rto "$run_dir" "$SECONDS"
)
}
