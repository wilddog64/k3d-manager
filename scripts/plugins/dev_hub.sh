#!/usr/bin/env bash
set -euo pipefail

DEV_HUB_NAME="dev-hub"
DEV_HUB_NAMESPACE="dev-hub"
DEV_HUB_CONTEXT="k3d-k3d-cluster"
DEV_HUB_LOCAL_PORT="11444"
DEV_HUB_KUBECONFIG="${HOME}/.kube/vclusters/dev-hub.yaml"
DEV_HUB_VALUES="${SCRIPT_DIR}/etc/vcluster/values-dev-hub.yaml"
DEV_HUB_CONFIG_DIR="${SCRIPT_DIR}/etc/dev-hub"
function _dev_hub_default_argocd_version() (
  # Source the canonical pin in a subshell so its other defaults do not leak into callers.
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/etc/argocd/vars.sh"
  printf '%s' "${ARGOCD_HELM_CHART_VERSION:-10.10.5}"
)
DEV_HUB_ARGOCD_VERSION="${ARGOCD_HELM_CHART_VERSION:-$(_dev_hub_default_argocd_version)}"
DEV_HUB_GRAFANA_VERSION="8.8.2"
DEV_HUB_KEYCHAIN_SERVICE="k3dm-dev-hub-grafana-admin"
DEV_HUB_KEYCHAIN_ACCOUNT="k3dm"

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
  fi
}

function _dev_hub_cluster_exists() {
  local output
  output="$(_run_command --no-exit --quiet -- "${_VCLUSTER_BIN}" list -n "${DEV_HUB_NAMESPACE}" --output json 2>/dev/null || true)"
  # shellcheck disable=SC2016
  _run_command --soft --quiet -- jq -e --arg name "${DEV_HUB_NAME}" 'any(.[]?; .Name == $name)' <<<"${output}" >/dev/null 2>&1
}

function _dev_hub_child_kubectl() {
  _run_command -- kubectl --kubeconfig "${DEV_HUB_KUBECONFIG}" "$@"
}

function _dev_hub_child_helm() {
  _run_command -- helm --kubeconfig "${DEV_HUB_KUBECONFIG}" "$@"
}

function _dev_hub_grafana_password() {
  local password restore_trace=0 stored_password
  case $- in *x*) restore_trace=1; set +x ;; esac
  if password="$(_run_command --no-exit --quiet -- security find-generic-password -w -s "${DEV_HUB_KEYCHAIN_SERVICE}" -a "${DEV_HUB_KEYCHAIN_ACCOUNT}" 2>/dev/null)" \
    && [[ -n "${password}" ]]; then
    printf '%s' "${password}"
    (( restore_trace == 0 )) || set -x
    return 0
  fi
  password="$(_run_command -- openssl rand -base64 24)" || return 1
  if [[ -z "${password}" ]]; then
    _err "dev-hub could not generate a non-empty Grafana admin password"
  fi
  printf 'add-generic-password -U -s %s -a %s -w %s\n' \
    "${DEV_HUB_KEYCHAIN_SERVICE}" "${DEV_HUB_KEYCHAIN_ACCOUNT}" "${password}" \
    | _run_command -- security -i >/dev/null
  if ! stored_password="$(_run_command --soft --quiet -- security find-generic-password -w \
    -s "${DEV_HUB_KEYCHAIN_SERVICE}" -a "${DEV_HUB_KEYCHAIN_ACCOUNT}" 2>/dev/null)"; then
    _err "dev-hub could not verify the Grafana admin password in Keychain"
  fi
  if [[ "${stored_password}" != "${password}" ]]; then
    _err "dev-hub Keychain password read-back did not match the generated Grafana admin password"
  fi
  printf '%s' "${password}"
  (( restore_trace == 0 )) || set -x
}

function _dev_hub_install_charts() (
  local temp_dir password secret_file
  set +x
  temp_dir="$(_run_command -- mktemp -d "${TMPDIR:-/tmp}/k3dm-dev-hub.XXXXXX")" || return 1
  [[ -n "${temp_dir}" ]] || return 1
  trap '_run_command --soft --quiet -- rm -rf -- "${temp_dir}" || true' EXIT
  password="$(_dev_hub_grafana_password)" || return 1
  [[ -n "${password}" ]] || return 1
  local yaml_password="${password//\'/\'\'}"
  secret_file="${temp_dir}/grafana-secret.yaml"
  _run_command -- cat >"${secret_file}" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: dev-hub-grafana-admin
  namespace: monitoring
type: Opaque
stringData:
  admin-user: admin
  admin-password: '${yaml_password}'
EOF
  unset password
  if ! _dev_hub_child_helm repo add --force-update argo https://argoproj.github.io/argo-helm \
    || ! _dev_hub_child_helm repo add --force-update grafana https://grafana.github.io/helm-charts \
    || ! _dev_hub_child_helm upgrade --install argocd argo/argo-cd -n cicd --create-namespace \
      --version "${DEV_HUB_ARGOCD_VERSION}" -f "${DEV_HUB_CONFIG_DIR}/argocd-values.yaml" --wait \
    || ! _dev_hub_child_kubectl apply -f "${DEV_HUB_CONFIG_DIR}/argocd-project.yaml"; then
    return 1
  fi
  if ! _dev_hub_child_kubectl create namespace monitoring --dry-run=client -o yaml | \
    _dev_hub_child_kubectl apply -f -; then
    return 1
  fi
  if ! _dev_hub_child_kubectl apply -f "${secret_file}" \
    || ! _dev_hub_child_helm upgrade --install dev-hub-grafana grafana/grafana -n monitoring \
      --version "${DEV_HUB_GRAFANA_VERSION}" -f "${DEV_HUB_CONFIG_DIR}/grafana-values.yaml" --wait; then
    return 1
  fi
)

function _dev_hub_apply_host_objects() {
  _dev_hub_host_kubectl apply -f "${DEV_HUB_CONFIG_DIR}/priorityclass.yaml"
  if ! _run_command --soft --quiet -- kubectl --context "${DEV_HUB_CONTEXT}" get namespace \
    "${DEV_HUB_NAMESPACE}" -n "${DEV_HUB_NAMESPACE}" >/dev/null 2>&1; then
    _dev_hub_host_kubectl create namespace "${DEV_HUB_NAMESPACE}" -n "${DEV_HUB_NAMESPACE}"
  fi
  _dev_hub_host_kubectl apply -n "${DEV_HUB_NAMESPACE}" -f "${DEV_HUB_CONFIG_DIR}/resourcequota.yaml"
  _dev_hub_host_kubectl apply -n "${DEV_HUB_NAMESPACE}" -f "${DEV_HUB_CONFIG_DIR}/limitrange.yaml"
}

function _dev_hub_ensure_kubeconfig() {
  if [[ ! -s "${DEV_HUB_KUBECONFIG}" ]]; then
    if ! ( _vcluster_export_kubeconfig "${DEV_HUB_NAME}" ); then
      _err "dev-hub could not export its kubeconfig; run make dev-hub-status to inspect the vCluster"
    fi
    if [[ ! -s "${DEV_HUB_KUBECONFIG}" ]]; then
      _run_command --soft --quiet -- rm -f -- "${DEV_HUB_KUBECONFIG}" || true
      _err "dev-hub kubeconfig export produced an empty file at '${DEV_HUB_KUBECONFIG}'"
    fi
  fi
}

function _dev_hub_wait_ready() {
  if ! ( _vcluster_refresh_connection "${DEV_HUB_NAME}" ); then
    _err "dev-hub connection refresh failed for vCluster '${DEV_HUB_NAME}'"
  fi
  local ready_rc=0 attempt
  for attempt in 1 2 3 4 5; do
    ready_rc=0
    _run_command --soft --quiet -- kubectl --kubeconfig "${DEV_HUB_KUBECONFIG}" \
      --request-timeout=5s get --raw=/readyz >/dev/null 2>&1 || ready_rc=$?
    if (( ready_rc == 0 )); then
      break
    fi
    if (( attempt < 5 )); then
      _run_command -- sleep 2
    fi
  done
  if (( ready_rc != 0 )); then
    _err "dev-hub is unreachable; if the vCluster was recreated, remove ${DEV_HUB_KUBECONFIG} and rerun make dev-hub-up"
  fi
}

function _dev_hub_check_replicated_service() {
  local replicated_service service_rc=0 service_attempt
  for service_attempt in 1 2 3 4 5; do
    service_rc=0
    replicated_service="$(_run_command --soft --quiet -- kubectl --kubeconfig "${DEV_HUB_KUBECONFIG}" \
      --request-timeout=5s -n monitoring get service hub-prometheus --ignore-not-found -o name 2>/dev/null)" || service_rc=$?
    if (( service_rc == 0 )) && [[ "${replicated_service}" == "service/hub-prometheus" ]]; then
      break
    fi
    if (( service_rc == 0 )) && [[ -z "${replicated_service}" ]]; then
      break
    fi
    if (( service_attempt < 5 )); then
      _run_command -- sleep 2
    fi
  done
  if (( service_rc != 0 )); then
    _err "dev-hub is unreachable while checking Service hub-prometheus; run make dev-hub-status to inspect it"
  fi
  if [[ "${replicated_service}" != "service/hub-prometheus" ]]; then
    _err "dev-hub is missing replicated Service hub-prometheus; run make dev-hub-down then make dev-hub-up"
  fi
}

function dev_hub_up() {
  _dev_hub_load_vcluster
  _dev_hub_require_host_context || return 1
  _vcluster_check_prerequisites
  local existing_cluster=0
  _dev_hub_apply_host_objects

  if ! _dev_hub_cluster_exists; then
    vcluster_create "${DEV_HUB_NAME}"
    if [[ "${DRY_RUN:-0}" == 1 ]]; then
      printf 'DRY_RUN: would install argo-cd %s and grafana %s into the dev-hub vCluster\n' \
        "${DEV_HUB_ARGOCD_VERSION}" "${DEV_HUB_GRAFANA_VERSION}"
      return 0
    fi
    if [[ ! -s "${DEV_HUB_KUBECONFIG}" ]]; then
      _run_command --soft --quiet -- rm -f -- "${DEV_HUB_KUBECONFIG}" || true
      _err "dev-hub vCluster creation did not produce a non-empty kubeconfig at '${DEV_HUB_KUBECONFIG}'"
    fi
  else
    existing_cluster=1
    _info "vCluster '${DEV_HUB_NAME}' already exists in namespace '${DEV_HUB_NAMESPACE}'"
    _dev_hub_ensure_kubeconfig
  fi
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    printf 'DRY_RUN: would install argo-cd %s and grafana %s into the dev-hub vCluster\n' \
      "${DEV_HUB_ARGOCD_VERSION}" "${DEV_HUB_GRAFANA_VERSION}"
    return 0
  fi
  _dev_hub_wait_ready
  if (( existing_cluster == 1 )); then
    _dev_hub_check_replicated_service
  fi
  _dev_hub_install_charts
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
  # shellcheck disable=SC2016
  phase="$(_run_command -- jq -r --arg name "${DEV_HUB_NAME}" '.[]? | select(.Name == $name) | (.Status // .Phase // "Unknown")' <<<"${clusters}" | _run_command -- head -1)"
  [[ -n "${phase}" ]] || phase="NotFound"
  quota="$(_dev_hub_host_kubectl get resourcequota -n "${DEV_HUB_NAMESPACE}" -o json 2>/dev/null || printf '{}')"
  used_memory="$(_run_command -- jq -r '.items[0].status.used["limits.memory"] // "unknown"' <<<"${quota}")"
  hard_memory="$(_run_command -- jq -r '.items[0].status.hard["limits.memory"] // "unknown"' <<<"${quota}")"
  used_cpu="$(_run_command -- jq -r '.items[0].status.used["limits.cpu"] // "unknown"' <<<"${quota}")"
  hard_cpu="$(_run_command -- jq -r '.items[0].status.hard["limits.cpu"] // "unknown"' <<<"${quota}")"
  printf 'vCluster phase: %s\n' "${phase}"
  printf 'Quota limits.memory used/hard: %s / %s\n' "${used_memory}" "${hard_memory}"
  printf 'Quota limits.cpu used/hard: %s / %s\n' "${used_cpu}" "${hard_cpu}"
  local branch
  branch="$(_run_command --soft --quiet -- kubectl --kubeconfig "${DEV_HUB_KUBECONFIG}" \
    get applicationset grafana-dashboards-hub -n cicd \
    -o 'jsonpath={.spec.template.spec.sources[0].targetRevision}' 2>/dev/null || true)"
  [[ -n "${branch}" ]] || branch="unknown"
  printf 'ApplicationSet targetRevision: %s\n' "${branch}"
  printf 'Grafana port-forward: kubectl --kubeconfig %s -n monitoring port-forward svc/dev-hub-grafana 13000:80\n' "${DEV_HUB_KUBECONFIG}"
  printf 'Grafana URL: http://127.0.0.1:13000\n'
}

function dev_hub_sync() { (
  _dev_hub_load_vcluster
  local branch="${1:-${BRANCH:-}}" local_ref remote_ref remote_output appset rendered
  if [[ -z "${branch}" ]]; then
    branch="$(_run_command -- git rev-parse --abbrev-ref HEAD)" || {
      _err "dev-hub-sync: could not determine the current branch"
    }
    [[ -n "${branch}" ]] || _err "dev-hub-sync: current branch lookup returned an empty name"
  fi
  if [[ ! "${branch}" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ || "${branch}" == *..* || "${branch}" == */ ]]; then
    _err "dev-hub-sync: invalid branch name '${branch}'"
  fi
  case "${branch}" in
    main|deploy/hub)
      _err "dev-hub-sync refuses protected branch '${branch}'"
      ;;
  esac
  local_ref="$(_run_command -- git rev-parse "refs/heads/${branch}")" || return 1
  remote_output="$(_run_command -- git ls-remote --heads origin "refs/heads/${branch}")"
  read -r remote_ref _ <<<"${remote_output}"
  if [[ -z "${remote_ref}" || "${local_ref}" != "${remote_ref}" ]]; then
    _err "dev-hub-sync: '${branch}' head is not present on origin"
  fi
  appset="${SCRIPT_DIR}/etc/argocd/applicationsets/grafana-dashboards-hub.yaml"
  rendered="$(_run_command -- mktemp "${TMPDIR:-/tmp}/k3dm-dev-hub-appset.XXXXXX")" || {
    _err "dev-hub-sync: could not create the rendered ApplicationSet file"
  }
  [[ -n "${rendered}" ]] || {
    _err "dev-hub-sync: mktemp returned an empty rendered ApplicationSet path"
  }
  trap '_run_command --soft --quiet -- rm -f -- "${rendered}" || true' EXIT
  export ARGOCD_NAMESPACE=cicd K3D_MANAGER_BRANCH="${branch}"
  # shellcheck disable=SC2016
  _run_command -- envsubst '$ARGOCD_NAMESPACE $K3D_MANAGER_BRANCH' <"${appset}" >"${rendered}"
  _dev_hub_child_kubectl apply -f "${rendered}"
)
}
