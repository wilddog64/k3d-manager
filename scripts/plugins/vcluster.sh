#!/usr/bin/env bash
set -euo pipefail

VCLUSTER_NAMESPACE="${VCLUSTER_NAMESPACE:-vclusters}"
VCLUSTER_VERSION="${VCLUSTER_VERSION:-0.32.1}"
VCLUSTER_KUBECONFIG_DIR="${VCLUSTER_KUBECONFIG_DIR:-${HOME}/.kube/vclusters}"
VCLUSTER_INSTALL_DIR="${VCLUSTER_INSTALL_DIR:-/usr/local/bin}"
export VCLUSTER_NAMESPACE
export VCLUSTER_VERSION
export VCLUSTER_KUBECONFIG_DIR
export VCLUSTER_INSTALL_DIR

function vcluster_create() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    _err "Usage: vcluster_create <name>"
  fi

  _vcluster_check_prerequisites
  local values_file
  values_file="$(_vcluster_values_file)"
  local target_kubeconfig
  target_kubeconfig="$(_vcluster_kubeconfig_path "$name")"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf 'DRY_RUN: vcluster create %s in namespace %s (chart %s)\n' "$name" "$VCLUSTER_NAMESPACE" "$VCLUSTER_VERSION"
    printf 'DRY_RUN: kubeconfig will be written to %s\n' "$target_kubeconfig"
    return 0
  fi

  _run_command -- vcluster create "$name" -n "$VCLUSTER_NAMESPACE" \
    --chart-version "$VCLUSTER_VERSION" --connect=false -f "$values_file"
  _vcluster_wait_ready "$name"
  _vcluster_export_kubeconfig "$name"
  _info "vCluster '$name' created; run ./scripts/k3d-manager vcluster_use $name to switch context"
}

function vcluster_destroy() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    _err "Usage: vcluster_destroy <name>"
  fi

  _vcluster_check_prerequisites
  _vcluster_ensure_exists "$name"
  local kubeconfig_path
  kubeconfig_path="$(_vcluster_kubeconfig_path "$name")"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf 'DRY_RUN: vcluster delete %s in namespace %s\n' "$name" "$VCLUSTER_NAMESPACE"
    printf 'DRY_RUN: kubeconfig %s would be removed\n' "$kubeconfig_path"
    return 0
  fi

  _run_command -- vcluster delete "$name" -n "$VCLUSTER_NAMESPACE" --wait
  if [[ -f "$kubeconfig_path" ]]; then
    _run_command -- rm -f "$kubeconfig_path"
  fi
  _info "Deleted vCluster '$name'"
}

function vcluster_use() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    _err "Usage: vcluster_use <name>"
  fi

  _vcluster_check_prerequisites

  local kubeconfig
  kubeconfig="$(_vcluster_kubeconfig_path "$name")"
  if [[ ! -f "$kubeconfig" ]]; then
    _err "kubeconfig for vCluster '$name' not found at $kubeconfig"
  fi

  local base_config
  if [[ -n "${KUBECONFIG:-}" ]]; then
    IFS=':' read -r base_config _ <<< "${KUBECONFIG}"
  else
    base_config="${HOME}/.kube/config"
  fi
  if [[ -z "$base_config" ]]; then
    base_config="${HOME}/.kube/config"
  fi

  local base_dir=""
  if [[ "$base_config" == */* ]]; then
    base_dir="${base_config%/*}"
  else
    base_dir="."
  fi
  if [[ -z "$base_dir" ]]; then
    base_dir="/"
  fi
  _run_command -- mkdir -p "$base_dir"

  local merge_chain="${KUBECONFIG:-$base_config}"
  local merged=""
  merged="$(
    _run_command -- env KUBECONFIG="${kubeconfig}:${merge_chain}" kubectl config view --flatten
  )"
  _write_sensitive_file "$base_config" "$merged"
  export KUBECONFIG="$base_config"

  local context
  context="$(_vcluster_context_from_file "$kubeconfig")"
  if [[ -n "$context" ]]; then
    _run_command -- kubectl config use-context "$context"
    _info "Active context: $context"
  else
    _warn "Unable to detect vCluster context from $kubeconfig"
  fi
}

function vcluster_list() {
  _vcluster_check_prerequisites
  _run_command -- vcluster list -n "$VCLUSTER_NAMESPACE"
}

function _vcluster_install_cli() {
  if _command_exist vcluster; then
    _info "vcluster already installed, skipping"
    return 0
  fi

  if _is_mac; then
    _run_command -- brew install loft-sh/tap/vcluster
  else
    local install_dir="${VCLUSTER_INSTALL_DIR:-/usr/local/bin}"
    local tmp_file
    tmp_file="$(mktemp -t vcluster-cli.XXXXXX)"
    trap '$(_cleanup_trap_command "$tmp_file")' RETURN
    local machine_arch
    machine_arch="$(uname -m)"
    local dl_arch
    case "$machine_arch" in
      x86_64)          dl_arch="amd64" ;;
      aarch64|arm64)   dl_arch="arm64" ;;
      *)               _err "Unsupported architecture for vcluster CLI install: $machine_arch" ;;
    esac
    local url="https://github.com/loft-sh/vcluster/releases/download/v${VCLUSTER_VERSION}/vcluster-linux-${dl_arch}"
    _run_command -- curl -fsSL -o "$tmp_file" "$url"
    _run_command -- chmod +x "$tmp_file"
    _run_command --prefer-sudo -- mkdir -p "$install_dir"
    _run_command --prefer-sudo -- mv "$tmp_file" "${install_dir%/}/vcluster"
    trap - RETURN
  fi

  if ! _command_exist vcluster; then
    _err "vcluster CLI installation failed"
  fi
}

function _vcluster_check_prerequisites() {
  if ! _command_exist vcluster; then
    _info "vcluster CLI not found — installing automatically"
    _vcluster_install_cli
  fi
  if ! _kubectl --no-exit --quiet cluster-info >/dev/null 2>&1; then
    _err "Host cluster context not available; kubectl cluster-info failed"
  fi
}

function _vcluster_wait_ready() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    _err "vCluster name required"
  fi
  local selector="app=vcluster,release=${name}"
  _kubectl -n "$VCLUSTER_NAMESPACE" wait --for=condition=Ready --timeout=300s pod -l "$selector"
}

function _vcluster_export_kubeconfig() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    _err "vCluster name required"
  fi
  _run_command -- mkdir -p "$VCLUSTER_KUBECONFIG_DIR"
  local kubeconfig
  kubeconfig="$(_vcluster_kubeconfig_path "$name")"
  local config
  config="$(_run_command -- vcluster connect "$name" -n "$VCLUSTER_NAMESPACE" --print)"
  _write_sensitive_file "$kubeconfig" "$config"
  _info "Kubeconfig written to $kubeconfig"
}

function _vcluster_values_file() {
  local file="${SCRIPT_DIR}/etc/vcluster/values.yaml"
  if [[ ! -f "$file" ]]; then
    _err "vCluster values file not found at $file"
  fi
  printf '%s\n' "$file"
}

function _vcluster_kubeconfig_path() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    _err "vCluster name required"
  fi
  if [[ ! "$name" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
    _err "vCluster name must be a valid DNS label (lowercase alphanumeric and hyphens, no leading/trailing hyphen): $name"
  fi
  printf '%s/%s.yaml\n' "$VCLUSTER_KUBECONFIG_DIR" "$name"
}

function _vcluster_ensure_exists() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    _err "vCluster name required"
  fi
  local kubeconfig
  kubeconfig="$(
    _vcluster_kubeconfig_path "$name"
  )"
  if [[ -f "$kubeconfig" ]]; then
    return 0
  fi
  local list_output=""
  if ! list_output="$(_run_command --no-exit --quiet -- vcluster list -n "$VCLUSTER_NAMESPACE")"; then
    _err "vCluster '$name' not found in namespace '$VCLUSTER_NAMESPACE'"
  fi
  local found=0 line cluster_name
  while IFS= read -r line; do
    [[ "$line" == NAME* ]] && continue
    read -r cluster_name _ <<< "$line"
    if [[ "$cluster_name" == "$name" ]]; then
      found=1
      break
    fi
  done <<< "$list_output"
  if [[ $found -eq 0 ]]; then
    _err "vCluster '$name' not found in namespace '$VCLUSTER_NAMESPACE'"
  fi
}

function _vcluster_context_from_file() {
  local file="${1:-}"
  if [[ -z "$file" || ! -f "$file" ]]; then
    return 1
  fi
  local line context=""
  while IFS= read -r line; do
    case "$line" in
      current-context:*)
        context="${line#current-context:}"
        while [[ "${context:0:1}" == ' ' || "${context:0:1}" == $'\t' ]]; do
          context="${context:1}"
        done
        break
        ;;
    esac
  done < "$file"
  printf '%s' "$context"
}
