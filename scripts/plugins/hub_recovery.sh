#!/usr/bin/env bash
set -euo pipefail

# Hub recovery preflight. This module deliberately maps durable local-path
# claims by namespace/claim, never by an old PVC UID or Docker volume name.

HUB_RECOVERY_SOURCE_DIR="${HUB_RECOVERY_SOURCE_DIR:-}"
HUB_RECOVERY_LOCAL_PATH_ROOT="${HUB_RECOVERY_LOCAL_PATH_ROOT:-/var/lib/rancher/k3s/storage}"
HUB_RECOVERY_TAR_BIN="${HUB_RECOVERY_TAR_BIN:-tar}"
HUB_RECOVERY_DOCKER_BIN="${HUB_RECOVERY_DOCKER_BIN:-docker}"

VAULT_PLUGIN="$PLUGINS_DIR/vault.sh"
if [[ -r "$VAULT_PLUGIN" ]]; then
  # shellcheck disable=SC1090
  source "$VAULT_PLUGIN"
fi
ARGOCD_PLUGIN="$PLUGINS_DIR/argocd.sh"
if [[ -r "$ARGOCD_PLUGIN" ]]; then
  # shellcheck disable=SC1090
  source "$ARGOCD_PLUGIN"
fi
KEYCLOAK_PLUGIN="$PLUGINS_DIR/keycloak.sh"
if [[ -r "$KEYCLOAK_PLUGIN" ]]; then
  # shellcheck disable=SC1090
  source "$KEYCLOAK_PLUGIN"
fi

function _hub_recovery_render_cloudflared_config() {
  local provider="$1" in_file="$2" table="$3"
  awk -v provider="$provider" -v table="$table" '
    BEGIN {
      while ((getline line < table) > 0) {
        if (line ~ /^#/ || line == "") continue
        split(line, f, "\\t")
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

function _hub_recovery_sync_vault_root_token() {
  local hub_context="$1" root_token=""
  if ! _is_mac; then
    _info "[hub-recovery] Vault root token Keychain sync skipped (macOS only)"
    return 0
  fi
  root_token=$(_kubectl -- --context "$hub_context" -n secrets get secret vault-root -o jsonpath='{.data.root_token}' 2>/dev/null | base64 --decode 2>/dev/null || true)
  if [[ -n "$root_token" ]]; then
    printf 'add-generic-password -U -s %s -a %s -w %s\n' "k3dm-vault-root-token" "$hub_context" "$root_token" | _no_trace security -i >/dev/null
    return 0
  fi
  root_token=$(_no_trace security find-generic-password -s "k3dm-vault-root-token" -a "$hub_context" -w 2>/dev/null || true)
  if [[ -z "$root_token" ]]; then
    _err "[hub-recovery] Vault root token is absent from both cluster and Keychain"
    return 1
  fi
  jq -n --arg root_token "$root_token" '{apiVersion:"v1",kind:"Secret",metadata:{name:"vault-root",namespace:"secrets"},type:"Opaque",stringData:{root_token:$root_token}}' | _kubectl -- --context "$hub_context" apply -f -
}

function _hub_recovery_ensure_eso_apps_role() {
  local ldap_vars_file="$SCRIPT_DIR/etc/ldap/vars.sh" role_json
  # shellcheck disable=SC1090
  source "$ldap_vars_file"
  _vault_ensure_eso_apps_policy secrets vault secret || return 1
  role_json=$(_vault_exec --no-exit secrets "vault read -format=json auth/kubernetes/role/${LDAP_ESO_ROLE}" vault 2>/dev/null || true)
  if ! printf '%s' "$role_json" | jq -e '.data.token_policies | index("eso-apps")' >/dev/null 2>&1; then
    _vault_configure_secret_reader_role secrets vault "$LDAP_ESO_SERVICE_ACCOUNT" "$LDAP_NAMESPACE" "$LDAP_VAULT_KV_MOUNT" "$LDAP_VAULT_POLICY_PREFIX" "$LDAP_ESO_ROLE" || return 1
  fi
}

function _hub_recovery_seed_app_cluster_reader() {
  local hub_context="$1" app_context="$2" server ca_data bearer_token root_token payload
  if ! _kubectl -- --context "$app_context" get namespace platform >/dev/null 2>&1; then
    _warn "[hub-recovery] app context '${app_context}' unavailable; skipping CVE reader seed"
    return 0
  fi
  server=$(_kubectl -- --context "$app_context" config view -o "jsonpath={.clusters[?(@.name==\"${app_context}\")].cluster.server}" 2>/dev/null || true)
  ca_data=$(_kubectl -- --context "$app_context" -n platform get secret hub-cve-inventory-reader-token -o jsonpath='{.data.ca\.crt}' 2>/dev/null || true)
  bearer_token=$(_kubectl -- --context "$app_context" -n platform get secret hub-cve-inventory-reader-token -o jsonpath='{.data.token}' 2>/dev/null | base64 --decode 2>/dev/null || true)
  payload=$(jq -n --arg server "$server" --arg caData "$ca_data" --arg bearerToken "$bearer_token" '{server:$server,caData:$caData,bearerToken:$bearerToken}')
  if ! printf '%s' "$payload" | jq -e '.server != "" and .caData != "" and .bearerToken != ""' >/dev/null; then
    _warn "[hub-recovery] CVE reader ServiceAccount Secret unavailable; skipping seed"
    return 0
  fi
  root_token=$(_kubectl -- --context "$hub_context" -n secrets get secret vault-root -o jsonpath='{.data.root_token}' 2>/dev/null | base64 --decode 2>/dev/null || true)
  [[ -n "$root_token" ]] || { _err "[hub-recovery] Vault root token unavailable for CVE reader seed"; return 1; }
  printf '%s\n%s\n' "$root_token" "$payload" | _no_trace _kubectl -- --context "$hub_context" -n secrets exec -i vault-0 -- sh -c 'read -r VAULT_TOKEN; export VAULT_TOKEN; vault kv put -mount=secret platform-ops/app-cluster-hostinger -'
}

function _hub_recovery_scale_openldap() {
  local hub_context="$1" replicas target_replicas="${HUB_RECOVERY_OPENLDAP_REPLICAS:-1}"
  replicas=$(_kubectl -- --context "$hub_context" -n identity get sts openldap -o jsonpath='{.spec.replicas}' 2>/dev/null || true)
  if [[ "$replicas" == "0" ]]; then
    _kubectl -- --context "$hub_context" -n identity scale sts openldap --replicas="$target_replicas" || return 1
    _kubectl -- --context "$hub_context" -n identity rollout status sts/openldap --timeout=180s
  fi
}

function _hub_recovery_replay_identity_hook() {
  local hub_context="$1" phase="" elapsed
  _kubectl -- --context "$hub_context" -n cicd patch application shopping-cart-identity --type merge -p '{"operation":{"initiatedBy":{"username":"hub_recovery_reconcile"},"sync":{"prune":false,"syncStrategy":{"hook":{}}}}}' || return 1
  for ((elapsed=0; elapsed<300; elapsed+=5)); do
    phase=$(_kubectl -- --context "$hub_context" -n cicd get application shopping-cart-identity -o jsonpath='{.status.operationState.phase}' 2>/dev/null || true)
    [[ "$phase" == "Succeeded" ]] && return 0
    sleep 5
  done
  _err "[hub-recovery] identity hook replay did not succeed (phase: ${phase:-unknown})"
  return 1
}

function _hub_recovery_install_cloudflared_config() {
  local config_dir="${HOME}/.cloudflared" config_file="${HOME}/.cloudflared/config.yml" source_file="$SCRIPT_DIR/etc/cloudflared/config.yml" table="$SCRIPT_DIR/etc/cloudflared/origins.tsv" rendered timestamp
  rendered=$(mktemp -t hub-recovery-cloudflared.XXXXXX)
  trap 'rm -f "$rendered"' RETURN
  _hub_recovery_render_cloudflared_config k3d "$source_file" "$table" > "$rendered"
  if ! cmp -s "$rendered" "$config_file"; then
    mkdir -p "$config_dir"
    if [[ -f "$config_file" ]]; then
      timestamp=$(date -u +%Y%m%dT%H%M%SZ)
      cp "$config_file" "${config_file}.bak.${timestamp}"
    fi
    cp "$rendered" "$config_file"
  fi
  trap - RETURN
  rm -f "$rendered"
  _info "[hub-recovery] reload with: launchctl kickstart -k \"gui/$(id -u)/com.k3d-manager.cloudflare-tunnel\""
}

function hub_recovery_reconcile() {
  if [[ "${1:-}" == "--help" ]]; then
    echo "Usage: hub_recovery_reconcile [--confirm]"
    return 0
  fi
  local confirm=0 hub_context="${HUB_RECOVERY_HUB_CONTEXT:-k3d-k3d-cluster}" app_context="${HUB_RECOVERY_APP_CONTEXT:-ubuntu-hostinger}"
  if [[ "${1:-}" == "--confirm" ]]; then confirm=1
  elif [[ -n "${1:-}" ]]; then _err "[hub-recovery] only --confirm is accepted"; return 1; fi
  local -a steps=("Vault root token ↔ Keychain" "ESO policy" "Hub registration" "CVE reader credential" "OpenLDAP replicas" "Identity hook replay" "Smoke user" "Cloudflare origins")
  local index
  if (( ! confirm )); then
    for index in "${!steps[@]}"; do printf '%d. %s\n' "$((index + 1))" "${steps[index]}"; done
    return 0
  fi
  _hub_recovery_sync_vault_root_token "$hub_context" || return 1
  _hub_recovery_ensure_eso_apps_role || return 1
  ARGOCD_APP_CLUSTER_SERVER=https://kubernetes.default.svc ARGOCD_APP_CLUSTER_NAME=ubuntu-k3s ARGOCD_APP_CLUSTER_SECRET_NAME=ubuntu-k3s-app-cluster ARGOCD_APP_CLUSTER_PROVIDER=k3d ARGOCD_NAMESPACE=cicd register_app_cluster || return 1
  _hub_recovery_seed_app_cluster_reader "$hub_context" "$app_context" || return 1
  _hub_recovery_scale_openldap "$hub_context" || return 1
  _hub_recovery_replay_identity_hook "$hub_context" || return 1
  KEYCLOAK_BASE_URL="${KEYCLOAK_BASE_URL:-https://keycloak.3ai-talk.org}" keycloak_seed_smoke_user || return 1
  _hub_recovery_install_cloudflared_config
}

function _hub_recovery_records() {
  cat <<'EOF'
server-0|secrets|data-vault-0|node-server-0-storage
agent-1|identity|postgres-keycloak-pvc|node-agent-1-storage
agent-0|identity|ldap-data-pvc|node-agent-0-storage
agent-0|identity|data-openldap-0|node-agent-0-storage
agent-0|identity|ldap-config-pvc|node-agent-0-storage
agent-2|trivy-system|data-trivy-server-0|node-agent-2-storage
agent-0|monitoring|prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0|node-agent-0-storage
EOF
}

function _hub_recovery_source_dir() {
  local source_dir="${1:-$HUB_RECOVERY_SOURCE_DIR}"
  if [[ -z "$source_dir" || ! -d "$source_dir" ]]; then
    echo "Hub recovery source directory is required and must exist." >&2
    return 1
  fi
  printf '%s\n' "$source_dir"
}

function _hub_recovery_validate_files() {
  local source_dir="$1" required
  local -a required=(server-db/state.db server-token pv-pvc.yaml)
  for required in "${required[@]}"; do
    if [[ ! -e "$source_dir/$required" ]]; then
      echo "Missing required recovery input: $required" >&2
      return 1
    fi
  done
}

function _hub_recovery_claim_tree() {
  local source_dir="$1" namespace="$2" claim="$3" storage_dir="$4"
  local -a matches=()
  mapfile -t matches < <(find "$source_dir/$storage_dir" -mindepth 1 -maxdepth 1 -type d \
    -name "pvc-*_${namespace}_${claim}" -print | sort)
  if (( ${#matches[@]} != 1 )); then
    echo "Expected exactly one source tree for ${namespace}/${claim}; found ${#matches[@]}." >&2
    return 1
  fi
  printf '%s\n' "${matches[0]}"
}

function _hub_recovery_validate_claims() {
  local source_dir="$1" node namespace claim storage_dir tree
  local -a trees=()
  while IFS='|' read -r node namespace claim storage_dir; do
    tree="$(_hub_recovery_claim_tree "$source_dir" "$namespace" "$claim" "$storage_dir")" || return 1
    trees+=("$tree")
    if ! grep -Fq -- "name: $claim" "$source_dir/pv-pvc.yaml"; then
      echo "PV/PVC export does not contain claim name ${claim}." >&2
      return 1
    fi
  done < <(_hub_recovery_records)
  local found_count
  found_count=$(find "$source_dir"/node-*-storage -mindepth 1 -maxdepth 1 -type d \
    -name 'pvc-*' -print | wc -l | tr -d ' ')
  if [[ "$found_count" != "${#trees[@]}" ]]; then
    echo "Recovery source has ${found_count} PVC trees; expected ${#trees[@]}." >&2
    return 1
  fi
}

function hub_recovery_plan() {
  if [[ "${1:-}" == "--help" ]]; then
    echo "Usage: hub_recovery_plan <captured-recovery-directory>"
    return 0
  fi
  local source_dir node namespace claim storage_dir tree
  source_dir="$(_hub_recovery_source_dir "${1:-}")" || return 1
  _hub_recovery_validate_files "$source_dir" || return 1
  while IFS='|' read -r node namespace claim storage_dir; do
    tree="$(_hub_recovery_claim_tree "$source_dir" "$namespace" "$claim" "$storage_dir")" || return 1
    printf 'RESTORE node=%s claim=%s/%s source=%s\n' "$node" "$namespace" "$claim" "${tree#"$source_dir/"}"
  done < <(_hub_recovery_records)
}

function hub_recovery_validate() {
  if [[ "${1:-}" == "--help" ]]; then
    echo "Usage: hub_recovery_validate <captured-recovery-directory>"
    return 0
  fi
  local source_dir
  source_dir="$(_hub_recovery_source_dir "${1:-}")" || return 1
  _hub_recovery_validate_files "$source_dir" || return 1
  _hub_recovery_validate_claims "$source_dir" || return 1
  echo "Hub recovery source validated: seven logical claims, one source tree each."
}

function _hub_recovery_target_path() {
  local targets_file="$1" node="$2" namespace="$3" claim="$4"
  local -a matches=()
  mapfile -t matches < <(awk -F '|' -v n="$node" -v ns="$namespace" -v c="$claim" \
    '$1 == n && $2 == ns && $3 == c { print $5 }' "$targets_file")
  if (( ${#matches[@]} != 1 )); then
    echo "Expected exactly one target for ${namespace}/${claim}; found ${#matches[@]}." >&2
    return 1
  fi
  printf '%s\n' "${matches[0]}"
}

function _hub_recovery_target_node() {
  awk -F '|' -v n="$2" -v ns="$3" -v c="$4" '$1 == n && $2 == ns && $3 == c { print $4 }' "$1"
}

function _hub_recovery_validate_targets() {
  local targets_file="$1" node namespace claim storage_dir target target_node logical_node
  if [[ ! -r "$targets_file" ]]; then
    echo "Recovery target map is required and must be readable." >&2
    return 1
  fi
  while IFS='|' read -r node namespace claim storage_dir; do
    target="$(_hub_recovery_target_path "$targets_file" "$node" "$namespace" "$claim")" || return 1
    target_node="$(_hub_recovery_target_node "$targets_file" "$node" "$namespace" "$claim")"
    logical_node="$(_hub_recovery_logical_node "$target_node")" || return 1
    if [[ "$target" != "$HUB_RECOVERY_LOCAL_PATH_ROOT"/pvc-*"_${namespace}_${claim}" || "$logical_node" != "$node" ]]; then
      echo "Invalid or absent target for ${namespace}/${claim}." >&2
      return 1
    fi
  done < <(_hub_recovery_records)
}

function _hub_recovery_restore_one() {
  local source_tree="$1" target="$2" target_node="$3" node="$4" namespace="$5" claim="$6" apply="$7"
  printf 'RESTORE node=%s claim=%s/%s target=%s\n' "$node" "$namespace" "$claim" "$target"
  if [[ "$apply" == "1" ]]; then
    "$HUB_RECOVERY_TAR_BIN" -C "$source_tree" -cpf - . | "$HUB_RECOVERY_DOCKER_BIN" exec -i "$target_node" "$HUB_RECOVERY_TAR_BIN" -C "$target" -xpf -
  fi
}

function _hub_recovery_logical_node() {
  local hostname="$1"
  case "$hostname" in
    *-server-0) printf '%s\n' server-0 ;;
    *-agent-0) printf '%s\n' agent-0 ;;
    *-agent-1) printf '%s\n' agent-1 ;;
    *-agent-2) printf '%s\n' agent-2 ;;
    *) echo "Unsupported recovery node hostname: $hostname" >&2; return 1 ;;
  esac
}

function _hub_recovery_pv_target() {
  local pv_json="$1" namespace="$2" claim="$3" output
  output=$(jq -r --arg ns "$namespace" --arg claim "$claim" '
    [.items[] | select(.spec.claimRef.namespace == $ns and .spec.claimRef.name == $claim)
      | [([.spec.nodeAffinity.required.nodeSelectorTerms[].matchExpressions[]?
           | select(.key == "kubernetes.io/hostname") | .values[]] | first), .spec.local.path] | @tsv][]
  ' <<<"$pv_json")
  if [[ "$(printf '%s\n' "$output" | sed '/^$/d' | wc -l | tr -d ' ')" != "1" ]]; then
    echo "Expected exactly one PV target for ${namespace}/${claim}." >&2
    return 1
  fi
  printf '%s\n' "$output"
}

function hub_recovery_targets() {
  if [[ "${1:-}" == "--help" ]]; then
    echo "Usage: hub_recovery_targets [kube-context=k3d-k3d-cluster]"
    return 0
  fi
  local context="${1:-k3d-k3d-cluster}" pv_json node namespace claim storage_dir target node_name path logical_node
  pv_json="$(_kubectl --quiet -- --context "$context" get pv -o json)" || return 1
  while IFS='|' read -r node namespace claim storage_dir; do
    target="$(_hub_recovery_pv_target "$pv_json" "$namespace" "$claim")" || return 1
    IFS=$'\t' read -r node_name path <<<"$target"
    logical_node="$(_hub_recovery_logical_node "$node_name")" || return 1
    if [[ "$logical_node" != "$node" || -z "$path" ]]; then
      echo "PV target node mismatch for ${namespace}/${claim}." >&2
      return 1
    fi
    printf '%s|%s|%s|%s|%s\n' "$node" "$namespace" "$claim" "$node_name" "$path"
  done < <(_hub_recovery_records)
}

function hub_recovery_restore() {
  if [[ "${1:-}" == "--help" ]]; then
    echo "Usage: hub_recovery_restore <captured-recovery-directory> <new-targets.tsv> [--confirm]"
    return 0
  fi
  local source_dir="${1:-}" targets_file="${2:-}" apply=0
  if [[ "${3:-}" == "--confirm" ]]; then
    apply=1
  elif [[ -n "${3:-}" ]]; then
    echo "Only --confirm is accepted as the third argument." >&2
    return 1
  fi
  source_dir="$(_hub_recovery_source_dir "$source_dir")" || return 1
  _hub_recovery_validate_files "$source_dir" || return 1
  _hub_recovery_validate_claims "$source_dir" || return 1
  _hub_recovery_validate_targets "$targets_file" || return 1
  local node namespace claim storage_dir source_tree target target_node
  while IFS='|' read -r node namespace claim storage_dir; do
    source_tree="$(_hub_recovery_claim_tree "$source_dir" "$namespace" "$claim" "$storage_dir")" || return 1
    target="$(_hub_recovery_target_path "$targets_file" "$node" "$namespace" "$claim")" || return 1
    target_node="$(_hub_recovery_target_node "$targets_file" "$node" "$namespace" "$claim")"
    _hub_recovery_restore_one "$source_tree" "$target" "$target_node" "$node" "$namespace" "$claim" "$apply"
  done < <(_hub_recovery_records)
  if (( ! apply )); then
    echo "Dry-run only. Re-run with --confirm after stateful consumers are scaled down. Then run: hub_recovery_reconcile --confirm"
  fi
}
