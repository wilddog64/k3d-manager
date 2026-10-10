#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2329,SC2030,SC2031

set -euo pipefail

K3DM_HUB_DATA_REPO="${K3DM_HUB_DATA_REPO:-git@github-k3dm-hub-data:wilddog64/k3dm-hub-data.git}"
K3DM_HUB_DATA_DIR="${K3DM_HUB_DATA_DIR:-${HOME}/.k3dm/hub-data}"
K3DM_HUB_DATA_AGE_RECIPIENT="${K3DM_HUB_DATA_AGE_RECIPIENT:-${REPO_ROOT:-.}/scripts/etc/dr/age-recipient.txt}"
K3DM_HUB_DATA_CONTEXT="${K3DM_HUB_DATA_CONTEXT:-k3d-k3d-cluster}"
K3DM_HUB_DATA_RETAIN_DAYS="${K3DM_HUB_DATA_RETAIN_DAYS:-5}"
K3DM_HUB_DATA_PUSHGATEWAY_URL="${K3DM_HUB_DATA_PUSHGATEWAY_URL:-http://localhost:19094/metrics/job/k3dm-hub-data-export}"

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

function _hub_data_inventory() (
  local root="$1" ns="${VAULT_NS:-secrets}" release="${VAULT_RELEASE:-vault}" token paths users ldap cleanup=0
  _hub_data_revoke_root() { (( cleanup == 1 )) || return 0; _hub_data_vault_revoke "$token" "$ns" "$release" >/dev/null 2>&1 || true; }
  trap _hub_data_revoke_root EXIT
  token="$(_hub_data_inventory_token "$ns" "$release")" && [[ -n "$token" ]] || return 1
  cleanup=1
  paths="$(_hub_data_vault_kv_list "$token" "$ns" "$release" secret/)" || { _err "[hub-data] vault kv list secret/ failed"; return 1; }
  paths="$(_hub_data_kv_names "$paths")" || { _err "[hub-data] vault kv list secret/ returned no paths"; return 1; }
  users="$(_hub_data_keycloak_user_count _kubectl)"
  ldap="$(_hub_data_ldap_entry_count _kubectl)"
  [[ "$users" =~ ^[1-9][0-9]*$ && "$ldap" =~ ^[1-9][0-9]*$ ]] || return 1
  jq -n --argjson p "$paths" --argjson u "$users" --argjson l "$ldap" '{vault_paths:$p,keycloak_realm_user_count:$u,ldap_entry_count:$l}' > "${root}/inventory.json"
  _hub_data_vault_revoke "$token" "$ns" "$release" >/dev/null 2>&1; cleanup=0
)

function hub_data_export_setup() { (
  local ns="${VAULT_NS:-secrets}" release="${VAULT_RELEASE:-vault}" policy='path "secret/metadata/" { capabilities = ["list"] }' stage token listing cleanup=0
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
  if ! _kubectl --context "$DR_DRILL_CONTEXT" -n "$ns" scale "$workload" --replicas="$replicas"; then
    _err "[hub-data] unable to scale ${workload}"
    return 1
  fi
}

function _hub_data_apply_keycloak() {
  local manifest="${K3DM_HUB_DATA_POSTGRES_MANIFEST:-${REPO_ROOT:-.}/scripts/etc/dr/postgres-keycloak.yaml}"
  [[ -f "$manifest" ]] || { _err "[hub-data] missing ${manifest}"; return 1; }
  _kubectl --context "$DR_DRILL_CONTEXT" -n identity apply -f "$manifest"
}

function _hub_data_restore_one() {
  local ns="$1" claim="$2" encrypted node path identity source_dir source_name
  encrypted="$3"; node="$4"; path="$5"; identity="$(_secret_load_data k3dm-hub-data-age identity age)"; source_dir="${encrypted%/*}"; source_name="${encrypted##*/}"
  if [[ -f "$encrypted" ]]; then
    age -d -i <(printf '%s\n' "$identity") "$encrypted" | docker exec -i "k3d-${DR_DRILL_CLUSTER}-${node}" tar -C "$path" -xpf -
  else
    find "$source_dir" -name "${source_name}.part-*" -print | sort | xargs cat | age -d -i <(printf '%s\n' "$identity") - | docker exec -i "k3d-${DR_DRILL_CLUSTER}-${node}" tar -C "$path" -xpf -
  fi
}

function _hub_data_prepare_claim() {
  local stage="$1" ns="$2" claim="$3" encrypted="$4" node pv path actual logical storage size modes
  node="$(_hub_data_meta_field "${stage}/pv-pvc.yaml" "$ns" "$claim" logicalNode)"; storage="$(_hub_data_meta_field "${stage}/pv-pvc.yaml" "$ns" "$claim" storageClass)"
  size="$(_hub_data_meta_field "${stage}/pv-pvc.yaml" "$ns" "$claim" size)"; modes="$(_hub_data_meta_modes "${stage}/pv-pvc.yaml" "$ns" "$claim")"
  [[ -n "$node" && -n "$size" && -n "$storage" && -n "$modes" ]] || return 1
  _hub_data_scale "$ns" "$claim" 0 >/dev/null || return 1
  _kubectl --context "$DR_DRILL_CONTEXT" -n "$ns" delete pvc "$claim" --ignore-not-found >/dev/null
  { printf 'apiVersion: v1\nkind: PersistentVolumeClaim\nmetadata:\n  name: %s\n  namespace: %s\n  annotations:\n    volume.kubernetes.io/selected-node: k3d-%s-%s\nspec:\n  storageClassName: %s\n  accessModes:\n' "$claim" "$ns" "$DR_DRILL_CLUSTER" "$node" "$storage"; _hub_data_meta_modes "${stage}/pv-pvc.yaml" "$ns" "$claim" | sed 's/^/    - /'; printf '  resources:\n    requests:\n      storage: %s\n' "$size"; } | _kubectl --context "$DR_DRILL_CONTEXT" apply -f -
  _kubectl --context "$DR_DRILL_CONTEXT" -n "$ns" wait --for=jsonpath='{.status.phase}'=Bound "pvc/${claim}" --timeout=300s
  pv="$(_kubectl --context "$DR_DRILL_CONTEXT" -n "$ns" get pvc "$claim" -o jsonpath='{.spec.volumeName}')"
  actual="$(_kubectl --context "$DR_DRILL_CONTEXT" get pv "$pv" -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[?(@.key=="kubernetes.io/hostname")].values[0]}')"; logical="$(_hub_recovery_logical_node "$actual")"
  [[ "$logical" == "$node" ]] || { _err "[hub-data] PV node mismatch for ${ns}/${claim}"; return 1; }
  path="$(_kubectl --context "$DR_DRILL_CONTEXT" get pv "$pv" -o jsonpath='{.spec.local.path}')"
  printf '%s\t%s\t%s\t%s\n' "$ns" "$claim" "$node" "$path" >> "${stage}/restore-targets.tsv"
}

function _hub_data_copy_claim() {
  local stage="$1" ns="$2" claim="$3" encrypted="$4" node path
  IFS=$'\t' read -r _ _ node path < <(awk -v n="$ns" -v c="$claim" '$1 == n && $2 == c {print}' "${stage}/restore-targets.tsv")
  [[ -n "$node" && -n "$path" ]] || return 1
  _hub_data_restore_one "$ns" "$claim" "$encrypted" "$node" "$path"
}

function hub_data_restore() { (
  local stage repo latest ns claim created=0
  if [[ -z "${DR_DRILL_CONTEXT:-}" || -z "${DR_DRILL_CLUSTER:-}" ]]; then
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
  repo="${stage}/repo"; : > "${stage}/restore-targets.tsv"
  git clone --depth 1 --branch snapshots "$K3DM_HUB_DATA_REPO" "$repo"; chmod 700 "$repo"; latest="$(_hub_data_latest_export_dir "$repo")"; [[ -n "$latest" ]] || return 1
  _hub_data_verify_export "$latest" || return 1
  cp "$latest/pv-pvc.yaml" "$stage/pv-pvc.yaml"
  cp "$latest/inventory.json" "$stage/inventory.json"
  _hub_data_apply_keycloak || return 1
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
  _hub_data_vault_revoke "$token" "$ns" "$release" >/dev/null 2>&1; cleanup=0
) }
