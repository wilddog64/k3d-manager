#!/usr/bin/env bash
set -euo pipefail

DEV_HUB_NAME="dev-hub"
DEV_HUB_NAMESPACE="dev-hub"
DEV_HUB_CONTEXT="k3d-k3d-cluster"
DEV_HUB_LOCAL_PORT="11444"
DEV_HUB_KUBECONFIG="${HOME}/.kube/vclusters/dev-hub.yaml"
DEV_HUB_VALUES="${SCRIPT_DIR}/etc/vcluster/values-dev-hub.yaml"
DEV_HUB_CONFIG_DIR="${SCRIPT_DIR}/etc/dev-hub"

function _dev_hub_load_vcluster() {
  export VCLUSTER_NAMESPACE="${DEV_HUB_NAMESPACE}"
  export VCLUSTER_LOCAL_PORT="${DEV_HUB_LOCAL_PORT}"
  export VCLUSTER_VALUES_FILE="${DEV_HUB_VALUES}"
  export VCLUSTER_HOST_CONTEXT="${DEV_HUB_CONTEXT}"
  export VCLUSTER_KUBECONFIG_DIR="${HOME}/.kube/vclusters"
  if ! declare -f vcluster_create >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/plugins/vcluster.sh"
  fi
}

function _dev_hub_host_kubectl() {
  _run_command -- kubectl --context "${DEV_HUB_CONTEXT}" "$@"
}

function _dev_hub_require_host_context() {
  local current_context
  current_context="$(_run_command -- kubectl config current-context)"
  if [[ "${current_context}" != "${DEV_HUB_CONTEXT}" ]]; then
    _err "dev-hub requires current kubectl context '${DEV_HUB_CONTEXT}' (current: '${current_context}')"
    return 1
  fi
}

function _dev_hub_cluster_exists() {
  local output
  output="$(_run_command --no-exit --quiet -- "${_VCLUSTER_BIN}" list -n "${DEV_HUB_NAMESPACE}" --output json 2>/dev/null || true)"
  jq -e --arg name "${DEV_HUB_NAME}" 'any(.[]?; .Name == $name)' <<<"${output}" >/dev/null 2>&1
}

function dev_hub_up() {
  _dev_hub_load_vcluster
  _dev_hub_require_host_context || return 1
  _vcluster_check_prerequisites
  _dev_hub_host_kubectl apply -f "${DEV_HUB_CONFIG_DIR}/priorityclass.yaml"

  if ! _dev_hub_host_kubectl get namespace "${DEV_HUB_NAMESPACE}" -n "${DEV_HUB_NAMESPACE}" >/dev/null 2>&1; then
    _dev_hub_host_kubectl create namespace "${DEV_HUB_NAMESPACE}" -n "${DEV_HUB_NAMESPACE}"
  fi
  _dev_hub_host_kubectl apply -n "${DEV_HUB_NAMESPACE}" -f "${DEV_HUB_CONFIG_DIR}/resourcequota.yaml"
  _dev_hub_host_kubectl apply -n "${DEV_HUB_NAMESPACE}" -f "${DEV_HUB_CONFIG_DIR}/limitrange.yaml"

  if ! _dev_hub_cluster_exists; then
    vcluster_create "${DEV_HUB_NAME}"
  else
    _info "vCluster '${DEV_HUB_NAME}' already exists in namespace '${DEV_HUB_NAMESPACE}'"
  fi
}

function dev_hub_down() {
  _dev_hub_load_vcluster
  _dev_hub_require_host_context || return 1
  _vcluster_check_prerequisites
  _run_command --no-exit -- "${_VCLUSTER_BIN}" delete "${DEV_HUB_NAME}" -n "${DEV_HUB_NAMESPACE}" --wait || true
  _dev_hub_host_kubectl delete namespace "${DEV_HUB_NAMESPACE}" -n "${DEV_HUB_NAMESPACE}" --ignore-not-found
  _vcluster_remove_proxy "${DEV_HUB_NAME}"
  if [[ -f "${DEV_HUB_KUBECONFIG}" ]]; then
    _run_command -- rm -f -- "${DEV_HUB_KUBECONFIG}"
  fi
  _info "Removed development vCluster '${DEV_HUB_NAME}'"
}

function dev_hub_status() {
  _dev_hub_load_vcluster
  _dev_hub_require_host_context || return 1
  _vcluster_check_prerequisites
  local clusters quota phase used_memory hard_memory used_cpu hard_cpu
  clusters="$(_run_command --no-exit --quiet -- "${_VCLUSTER_BIN}" list -n "${DEV_HUB_NAMESPACE}" --output json 2>/dev/null || printf '[]')"
  phase="$(jq -r --arg name "${DEV_HUB_NAME}" '.[]? | select(.Name == $name) | (.Status // .Phase // "Unknown")' <<<"${clusters}" | head -1)"
  [[ -n "${phase}" ]] || phase="NotFound"
  quota="$(_dev_hub_host_kubectl get resourcequota -n "${DEV_HUB_NAMESPACE}" -o json 2>/dev/null || printf '{}')"
  used_memory="$(jq -r '.items[0].status.used["limits.memory"] // "unknown"' <<<"${quota}")"
  hard_memory="$(jq -r '.items[0].status.hard["limits.memory"] // "unknown"' <<<"${quota}")"
  used_cpu="$(jq -r '.items[0].status.used["limits.cpu"] // "unknown"' <<<"${quota}")"
  hard_cpu="$(jq -r '.items[0].status.hard["limits.cpu"] // "unknown"' <<<"${quota}")"
  printf 'vCluster phase: %s\n' "${phase}"
  printf 'Quota limits.memory used/hard: %s / %s\n' "${used_memory}" "${hard_memory}"
  printf 'Quota limits.cpu used/hard: %s / %s\n' "${used_cpu}" "${hard_cpu}"
}
