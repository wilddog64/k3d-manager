#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2016,SC2329,SC2030,SC2031

set -euo pipefail

K3DM_HUB_DATA_REPO="${K3DM_HUB_DATA_REPO:-git@github-k3dm-hub-data:wilddog64/k3dm-hub-data.git}"
K3DM_HUB_DATA_KEEP="${K3DM_HUB_DATA_KEEP:-4}"
K3DM_HUB_DATA_DIR="${K3DM_HUB_DATA_DIR:-${HOME}/.k3dm/hub-data}"
K3DM_HUB_DATA_AGE_RECIPIENT="${K3DM_HUB_DATA_AGE_RECIPIENT:-${REPO_ROOT:-.}/scripts/etc/dr/age-recipient.txt}"

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
  done < <(find "$root" -type f \( -name '*.age' -o -name '*.age.part-*' \) -print | sort)
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

function _hub_data_inventory() (
  local root="$1" ns="${VAULT_NS:-secrets}" release="${VAULT_RELEASE:-vault}" token paths users ldap cleanup=0
  _hub_data_revoke_root() { (( cleanup == 1 )) || return 0; _hub_data_vault_revoke "$token" "$ns" "$release" >/dev/null 2>&1 || true; }
  trap _hub_data_revoke_root EXIT
  token="$(_hub_data_generate_root "$ns" "$release")"; cleanup=1
  paths="$(_hub_data_vault_kv_list "$token" "$ns" "$release" secret/)"
  jq -e '.data | type == "array" and length > 0' <<<"$paths" >/dev/null
  users="$(_kubectl -n identity exec deployment/postgres-keycloak -- psql -U postgres -d keycloak -Atc "SELECT count(*) FROM user_entity WHERE realm_id=(SELECT id FROM realm WHERE name='${KEYCLOAK_REALM:-shopping-cart}');" 2>/dev/null | tr -d '[:space:]')"
  ldap="$(_kubectl -n identity exec statefulset/openldap -- ldapsearch -x -LLL -b "${LDAP_BASE_DN:-dc=shopping-cart,dc=local}" dn 2>/dev/null | awk '/^dn:/{n++} END{print n+0}')"
  [[ "$users" =~ ^[1-9][0-9]*$ && "$ldap" =~ ^[1-9][0-9]*$ ]] || return 1
  jq -n --argjson p "${paths:-null}" --argjson u "$users" --argjson l "$ldap" '{vault_paths:($p.data // $p),keycloak_realm_user_count:$u,ldap_entry_count:$l}' > "${root}/inventory.json"
  _hub_data_vault_revoke "$token" "$ns" "$release" >/dev/null 2>&1; cleanup=0
)

function hub_data_export() (
  [[ -r "$K3DM_HUB_DATA_AGE_RECIPIENT" ]] || { _err "[hub-data] missing age recipient: $K3DM_HUB_DATA_AGE_RECIPIENT"; return 1; }
  local stage repo root stamp ns claim logical path container
  stage="$(_hub_data_stage)"
  trap 'rm -rf -- "$stage"' EXIT
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
  _hub_data_inventory "$root"; _hub_data_split_large "$root"; _hub_data_encrypted_checksum "$root"
  (cd "$repo" && git add snapshots && git commit -m "snapshot: ${stamp}" && git push origin snapshots)
)

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
  local dir="${SHOPPING_CART_INFRA_ROOT:-${REPO_ROOT}/../shopping-cart-infra}/identity/keycloak" manifest
  [[ -d "$dir" ]] || return 1
  for manifest in "$dir"/*.yaml; do
    [[ -f "$manifest" ]] || continue
    if grep -Eq '^kind: (ExternalSecret|CronJob|ApplicationSet)$' "$manifest"; then continue; fi
    _kubectl --context "$DR_DRILL_CONTEXT" -n identity apply -f "$manifest"
  done
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
  if ! _hub_data_scale "$ns" "$claim" 0 >/dev/null 2>&1; then
    _err "[hub-data] unable to scale $(_hub_data_workload "$ns" "$claim")"
    return 1
  fi
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

function hub_data_restore() (
  local stage repo latest ns claim created=0
  if [[ -z "${DR_DRILL_CONTEXT:-}" || -z "${DR_DRILL_CLUSTER:-}" ]]; then
    _err "[hub-data] DR_DRILL_CONTEXT and DR_DRILL_CLUSTER are required"
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
  cp "$latest/pv-pvc.yaml" "$stage/pv-pvc.yaml"
  cp "$latest/inventory.json" "$stage/inventory.json"
  while read -r sum file; do
    [[ -f "${latest}/${file}" ]] || return 1
    if command -v sha256sum >/dev/null 2>&1; then printf '%s  %s\n' "$sum" "${latest}/${file}" | sha256sum -c - >/dev/null; else printf '%s  %s\n' "$sum" "${latest}/${file}" | shasum -a 256 -c - >/dev/null; fi
  done < "${latest}/SHA256SUMS"
  while IFS='|' read -r ns claim; do
    if ! _hub_data_prepare_claim "$stage" "$ns" "$claim" "${latest}/${ns}-${claim}.tar.age"; then return 1; fi
  done < <(_hub_data_claims)
  _hub_data_apply_keycloak
  while IFS='|' read -r ns claim; do
    _hub_data_copy_claim "$stage" "$ns" "$claim" "${latest}/${ns}-${claim}.tar.age" || return 1
  done < <(_hub_data_claims)
  while IFS='|' read -r ns claim; do
    if ! _hub_data_scale "$ns" "$claim" 1; then return 1; fi
  done < <(_hub_data_claims)
)

function hub_data_verify_vault_paths() (
  local ns="${1:-secrets}" release="${2:-vault}" inventory="${3:?inventory path required}" token cleanup=0 path
  local -a paths=()
  _hub_data_revoke_root() { (( cleanup == 1 )) || return 0; _hub_data_vault_revoke "$token" "$ns" "$release" >/dev/null 2>&1 || true; }
  trap _hub_data_revoke_root EXIT
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    [[ "$path" =~ ^[A-Za-z0-9_./-]+$ ]] || { _err "[hub-data] invalid Vault KV path: ${path}"; return 1; }
    paths+=("$path")
  done < <(jq -r '.vault_paths[]' "$inventory")
  token="$(_hub_data_generate_root "$ns" "$release")"; cleanup=1
  for path in "${paths[@]}"; do
    _hub_data_vault_kv_list "$token" "$ns" "$release" "$path" >/dev/null || return 1
  done
  _hub_data_vault_revoke "$token" "$ns" "$release" >/dev/null 2>&1; cleanup=0
)
