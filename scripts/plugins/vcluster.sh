#!/usr/bin/env bash
set -euo pipefail

VCLUSTER_NAMESPACE="${VCLUSTER_NAMESPACE:-vclusters}"
VCLUSTER_VERSION="${VCLUSTER_VERSION:-0.32.1}"
VCLUSTER_KUBECONFIG_DIR="${VCLUSTER_KUBECONFIG_DIR:-${HOME}/.kube/vclusters}"
VCLUSTER_VALUES_FILE="${VCLUSTER_VALUES_FILE:-}"
VCLUSTER_LOCAL_PORT="${VCLUSTER_LOCAL_PORT:-11443}"
_VCLUSTER_BIN=""
export VCLUSTER_NAMESPACE
export VCLUSTER_VERSION
export VCLUSTER_KUBECONFIG_DIR
export VCLUSTER_VALUES_FILE
export VCLUSTER_LOCAL_PORT

function _vcluster_load_argocd_plugin() {
  if declare -f _argocd_hub_kubectl_cmd >/dev/null 2>&1; then
    return 0
  fi

  local argocd_plugin="${SCRIPT_DIR}/plugins/argocd.sh"
  if [[ ! -r "${argocd_plugin}" ]]; then
    _err "ArgoCD plugin not found: ${argocd_plugin}"
  fi

  # shellcheck source=/dev/null
  source "${argocd_plugin}"
}

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

  _vcluster_reconcile_namespace "$name"
  _run_command -- "$_VCLUSTER_BIN" create "$name" -n "$VCLUSTER_NAMESPACE" \
    --chart-version "$VCLUSTER_VERSION" --connect=false -f "$values_file"
  _vcluster_wait_ready "$name"
  _vcluster_export_kubeconfig "$name"
  _info "vCluster '$name' created; run ./scripts/k3d-manager vcluster_use $name to switch context"
}

# vcluster create refuses a second virtual cluster in a namespace that already holds one,
# and VCLUSTER_NAMESPACE is shared by every run on a runner. One orphan therefore wedges
# every later run permanently, and each blocked run fails too early to clean up after
# itself. Clearing it here recovers from leaks no EXIT trap can catch, such as a SIGKILLed
# run. The _warn is deliberate: an orphan is always a bug, so a silent sweep would mask a
# teardown regression instead of surfacing it.
function _vcluster_reconcile_namespace() {
  local keep="${1:-}"
  local list_output="" line="" cluster_name=""
  list_output="$(_run_command --no-exit --quiet -- "$_VCLUSTER_BIN" list -n "$VCLUSTER_NAMESPACE" 2>/dev/null || true)"

  while IFS= read -r line; do
    [[ -z "$line" || "$line" == NAME* ]] && continue
    read -r cluster_name _ <<< "$line"
    [[ -z "$cluster_name" || "$cluster_name" == "$keep" ]] && continue
    _warn "vCluster '${cluster_name}' is an orphan in namespace '${VCLUSTER_NAMESPACE}' (its run never tore down); deleting it before creating '${keep}'"
    if ! _run_command --no-exit -- "$_VCLUSTER_BIN" delete "$cluster_name" -n "$VCLUSTER_NAMESPACE" --wait; then
      _warn "vcluster delete '${cluster_name}' failed; falling back to helm uninstall"
      _run_command --no-exit -- helm -n "$VCLUSTER_NAMESPACE" uninstall "$cluster_name" --wait || true
    fi
  done <<< "$list_output"

  return 0
}

function vcluster_destroy() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    _err "Usage: vcluster_destroy <name>"
  fi

  _vcluster_check_prerequisites
  local kubeconfig_path
  kubeconfig_path="$(_vcluster_kubeconfig_path "$name")"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf 'DRY_RUN: vcluster delete %s in namespace %s\n' "$name" "$VCLUSTER_NAMESPACE"
    printf 'DRY_RUN: kubeconfig %s would be removed\n' "$kubeconfig_path"
    printf 'DRY_RUN: deregister %s from hub ArgoCD (cluster-%s + %s-preflight-* appsets/apps)\n' "$name" "$name" "$name"
    return 0
  fi

  # After the dry-run return: the existence check queries the host, and a dry run must
  # execute nothing and must not depend on the vCluster being there to print its plan.
  _vcluster_ensure_exists "$name" || return 1

  _vcluster_deregister_from_hub "$name"
  if ! _run_command --no-exit -- "$_VCLUSTER_BIN" delete "$name" -n "$VCLUSTER_NAMESPACE" --wait; then
    _warn "vcluster delete '$name' failed (child API may be unreachable); falling back to helm uninstall"
    _run_command --no-exit -- helm -n "$VCLUSTER_NAMESPACE" uninstall "$name" --wait || true
  fi
  _vcluster_remove_proxy "$name"
  if [[ -f "$kubeconfig_path" ]]; then
    _run_command -- rm -f "$kubeconfig_path"
  fi
  _info "Deleted vCluster '$name'"
}

function _vcluster_deregister_from_hub() {
  local name="${1:-}"
  [[ -z "${name}" ]] && return 0

  _vcluster_load_argocd_plugin || return 1

  local ns="${ARGOCD_NAMESPACE:-cicd}"
  local -a hub_kubectl=()
  read -r -a hub_kubectl <<< "$(_argocd_hub_kubectl_cmd)"

  "${hub_kubectl[@]}" -n "${ns}" delete applicationset \
    -l "k3d-manager/preflight-cluster=${name}" --ignore-not-found >/dev/null 2>&1 || true

  local resource=""
  while IFS= read -r resource; do
    [[ -z "${resource}" ]] && continue
    "${hub_kubectl[@]}" -n "${ns}" delete "${resource}" --ignore-not-found >/dev/null 2>&1 || true
  done < <("${hub_kubectl[@]}" -n "${ns}" get applicationset -o name 2>/dev/null | grep "/${name}-preflight-" || true)

  while IFS= read -r resource; do
    [[ -z "${resource}" ]] && continue
    "${hub_kubectl[@]}" -n "${ns}" patch "${resource}" --type=merge \
      -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
    "${hub_kubectl[@]}" -n "${ns}" delete "${resource}" --ignore-not-found >/dev/null 2>&1 || true
  done < <("${hub_kubectl[@]}" -n "${ns}" get application -o name 2>/dev/null | grep "/${name}-preflight-" || true)

  "${hub_kubectl[@]}" -n "${ns}" delete secret "cluster-${name}" --ignore-not-found >/dev/null 2>&1 || true
  _info "Deregistered '${name}' from hub ArgoCD (${ns})"
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
  _run_command -- "$_VCLUSTER_BIN" list -n "$VCLUSTER_NAMESPACE"
}

function _vcluster_check_prerequisites() {
  if ! _VCLUSTER_BIN="$(foundation_ensure_vcluster_cli "$VCLUSTER_VERSION")" || [[ -z "${_VCLUSTER_BIN}" ]]; then
    _err "Unable to resolve the vCluster CLI through foundation_ensure_vcluster_cli for version ${VCLUSTER_VERSION}"
  fi
  local host_context="${VCLUSTER_HOST_CONTEXT:-$(_kubectl config current-context 2>/dev/null || true)}"
  if [[ -z "${host_context}" ]]; then
    _err "Host cluster context not available; set VCLUSTER_HOST_CONTEXT or configure a current kubectl context"
  fi
  if ! _kubectl --no-exit --quiet -- --context "${host_context}" get nodes >/dev/null 2>&1; then
    _err "Host cluster context not available: ${host_context}"
  fi
}

function _vcluster_wait_ready() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    _err "vCluster name required"
  fi
  local selector="app=vcluster,release=${name}"
  local timeout=60
  local interval=2
  local elapsed=0
  until _kubectl --no-exit --quiet -- -n "$VCLUSTER_NAMESPACE" \
    get pod -l "$selector" --no-headers 2>/dev/null | grep -q .; do
    sleep "$interval"
    elapsed=$((elapsed + interval))
    if (( elapsed >= timeout )); then
      _err "vCluster pod for '${name}' never appeared (selector: ${selector})"
    fi
  done
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
  config="$(_run_command -- "$_VCLUSTER_BIN" connect "$name" -n "$VCLUSTER_NAMESPACE" \
    --local-port "$VCLUSTER_LOCAL_PORT" --print)"
  _write_sensitive_file "$kubeconfig" "$config"
  _info "Kubeconfig written to $kubeconfig"
}

function _vcluster_remove_proxy() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    _err "vCluster name required"
  fi
  local proxy
  proxy="$(_run_command --quiet -- docker ps -a \
    --filter "name=vcluster_${name}_" --filter "name=background_proxy" \
    --format '{{.Names}}' | head -1)"
  if [[ -n "$proxy" ]]; then
    _run_command --quiet -- docker rm -f "$proxy" >/dev/null 2>&1 || true
  fi
}

function _vcluster_refresh_connection() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    _err "vCluster name required"
  fi
  _vcluster_remove_proxy "$name"
  _run_command --quiet -- "$_VCLUSTER_BIN" connect "$name" -n "$VCLUSTER_NAMESPACE" \
    --local-port "$VCLUSTER_LOCAL_PORT" --print >/dev/null 2>&1 || true
}

function _vcluster_values_file() {
  local file="${VCLUSTER_VALUES_FILE:-${SCRIPT_DIR}/etc/vcluster/values.yaml}"
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
  # A kubeconfig file is not a virtual cluster. Teardowns that never ran leave stale
  # kubeconfigs behind, so accepting one as proof made this predicate report a vCluster
  # that no longer exists. vcluster list is the only source of truth.
  #
  # Absence returns non-zero instead of _err, because _err is exit 1 and the caller
  # chain cannot catch that: _e2e_teardown guards vcluster_destroy with `|| _warn`, and
  # the exit skipped the proxy, kubeconfig and log cleanup that follows it.
  local list_output=""
  if ! list_output="$(_run_command --no-exit --quiet -- "$_VCLUSTER_BIN" list -n "$VCLUSTER_NAMESPACE")"; then
    _warn "vCluster '$name' not found in namespace '$VCLUSTER_NAMESPACE'"
    return 1
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
    _warn "vCluster '$name' not found in namespace '$VCLUSTER_NAMESPACE'"
    return 1
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
