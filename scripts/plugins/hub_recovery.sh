#!/usr/bin/env bash
set -euo pipefail

# Hub recovery preflight. This module deliberately maps durable local-path
# claims by namespace/claim, never by an old PVC UID or Docker volume name.

HUB_RECOVERY_SOURCE_DIR="${HUB_RECOVERY_SOURCE_DIR:-}"
HUB_RECOVERY_LOCAL_PATH_ROOT="${HUB_RECOVERY_LOCAL_PATH_ROOT:-/var/lib/rancher/k3s/storage}"
HUB_RECOVERY_TAR_BIN="${HUB_RECOVERY_TAR_BIN:-tar}"

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
    '$1 == n && $2 == ns && $3 == c { print $4 }' "$targets_file")
  if (( ${#matches[@]} != 1 )); then
    echo "Expected exactly one target for ${namespace}/${claim}; found ${#matches[@]}." >&2
    return 1
  fi
  printf '%s\n' "${matches[0]}"
}

function _hub_recovery_validate_targets() {
  local targets_file="$1" node namespace claim storage_dir target
  if [[ ! -r "$targets_file" ]]; then
    echo "Recovery target map is required and must be readable." >&2
    return 1
  fi
  while IFS='|' read -r node namespace claim storage_dir; do
    target="$(_hub_recovery_target_path "$targets_file" "$node" "$namespace" "$claim")" || return 1
    if [[ "$target" != "$HUB_RECOVERY_LOCAL_PATH_ROOT"/pvc-*"_${namespace}_${claim}" || ! -d "$target" ]]; then
      echo "Invalid or absent target for ${namespace}/${claim}." >&2
      return 1
    fi
  done < <(_hub_recovery_records)
}

function _hub_recovery_restore_one() {
  local source_tree="$1" target="$2" node="$3" namespace="$4" claim="$5" apply="$6"
  printf 'RESTORE node=%s claim=%s/%s target=%s\n' "$node" "$namespace" "$claim" "$target"
  if [[ "$apply" == "1" ]]; then
    "$HUB_RECOVERY_TAR_BIN" -C "$source_tree" -cpf - . | "$HUB_RECOVERY_TAR_BIN" -C "$target" -xpf -
  fi
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
  local node namespace claim storage_dir source_tree target
  while IFS='|' read -r node namespace claim storage_dir; do
    source_tree="$(_hub_recovery_claim_tree "$source_dir" "$namespace" "$claim" "$storage_dir")" || return 1
    target="$(_hub_recovery_target_path "$targets_file" "$node" "$namespace" "$claim")" || return 1
    _hub_recovery_restore_one "$source_tree" "$target" "$node" "$namespace" "$claim" "$apply"
  done < <(_hub_recovery_records)
  if (( ! apply )); then
    echo "Dry-run only. Re-run with --confirm after stateful consumers are scaled down."
  fi
}
