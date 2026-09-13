#!/usr/bin/env bash
# scripts/plugins/istio_ambient.sh — install Istio ambient mesh on an app cluster via ArgoCD

function deploy_istio_ambient() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: [APP_CLUSTER_NAME=<ctx>] [ARGOCD_CONTEXT=<hub-ctx>] ./scripts/k3d-manager deploy_istio_ambient

Applies the istio-ambient ApplicationSet to the hub ArgoCD (ARGOCD_CONTEXT, default
k3d-k3d-cluster), targeting APP_CLUSTER_NAME (default ubuntu-k3s). Preconditions:
  - The target cluster is registered with the hub ArgoCD (register_app_cluster).
  - AMBIENT_CNI_CONF_DIR/AMBIENT_CNI_BIN_DIR match the target cluster's CNI substrate.
    Defaults follow the target's k3d-manager/provider label (override with
    AMBIENT_CNI_PROVIDER): k3d → /var/lib/rancher/k3s/agent/etc/cni/net.d + /bin;
    k3s-hostinger → /var/lib/rancher/k3s/agent/etc/cni/net.d + /var/lib/rancher/k3s/data/cni;
    anything else (Cilium) → /etc/cni/net.d + /opt/cni/bin.
  - The platform AppProject permits istio-system as a destination for the target cluster.
HELP
    return 0
  fi

  local _appset="${SCRIPT_DIR}/etc/argocd/applicationsets/istio-ambient.yaml"
  : "${ARGOCD_NAMESPACE:=cicd}"
  : "${ARGOCD_CONTEXT:=k3d-k3d-cluster}"
  : "${APP_CLUSTER_NAME:=${ARGOCD_APP_CLUSTER_NAME:-ubuntu-k3s}}"
  : "${AMBIENT_ISTIO_VERSION:=1.24.2}"
  if [[ -z "${AMBIENT_CNI_CONF_DIR:-}" || -z "${AMBIENT_CNI_BIN_DIR:-}" ]]; then
    local _cni_provider _cni_dirs
    _cni_provider="${AMBIENT_CNI_PROVIDER:-$(_istio_ambient_target_provider "${ARGOCD_CONTEXT}" "${ARGOCD_NAMESPACE}" "${APP_CLUSTER_NAME}")}"
    _cni_dirs="$(_istio_ambient_cni_dirs "${_cni_provider}")"
    : "${AMBIENT_CNI_CONF_DIR:=${_cni_dirs%% *}}"
    : "${AMBIENT_CNI_BIN_DIR:=${_cni_dirs##* }}"
    _info "[istio_ambient] CNI dirs for provider '${_cni_provider:-unknown}': ${AMBIENT_CNI_CONF_DIR} ${AMBIENT_CNI_BIN_DIR}"
  fi
  export ARGOCD_NAMESPACE APP_CLUSTER_NAME AMBIENT_ISTIO_VERSION
  export AMBIENT_CNI_CONF_DIR AMBIENT_CNI_BIN_DIR

  if [[ ! -f "${_appset}" ]]; then
    _err "[istio_ambient] ApplicationSet not found: ${_appset}"
    return 1
  fi

  _info "[istio_ambient] Applying istio-ambient ApplicationSet (hub: ${ARGOCD_CONTEXT}, target: ${APP_CLUSTER_NAME})..."
  # shellcheck disable=SC2016
  if envsubst '$ARGOCD_NAMESPACE $APP_CLUSTER_NAME $AMBIENT_ISTIO_VERSION $AMBIENT_CNI_CONF_DIR $AMBIENT_CNI_BIN_DIR' < "${_appset}" \
      | _kubectl apply --context "${ARGOCD_CONTEXT}" -f -; then
    _info "[istio_ambient] Applied — ArgoCD will sync istio-system on ${APP_CLUSTER_NAME}"
  else
    _err "[istio_ambient] Failed to apply istio-ambient ApplicationSet"
    return 1
  fi
}

function _istio_ambient_cni_dirs() {
  case "${1:-}" in
    k3d)           printf '%s %s\n' /var/lib/rancher/k3s/agent/etc/cni/net.d /bin ;;
    k3s-hostinger) printf '%s %s\n' /var/lib/rancher/k3s/agent/etc/cni/net.d /var/lib/rancher/k3s/data/cni ;;
    *)             printf '%s %s\n' /etc/cni/net.d /opt/cni/bin ;;
  esac
}

function _istio_ambient_target_provider() {
  local context="$1" namespace="$2" cluster_name="$3" secret name
  while IFS= read -r secret; do
    [[ -z "${secret}" ]] && continue
    name="$(_kubectl --no-exit --context "${context}" -n "${namespace}" get "${secret}" -o jsonpath='{.data.name}' 2>/dev/null | base64 --decode 2>/dev/null || true)"
    if [[ "${name}" == "${cluster_name}" ]]; then
      _kubectl --no-exit --context "${context}" -n "${namespace}" get "${secret}" -o jsonpath='{.metadata.labels.k3d-manager/provider}' 2>/dev/null || true
      return 0
    fi
  done < <(_kubectl --no-exit --context "${context}" -n "${namespace}" get secrets -l argocd.argoproj.io/secret-type=cluster -o name 2>/dev/null)
}
