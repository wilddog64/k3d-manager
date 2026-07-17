#!/usr/bin/env bash
# scripts/plugins/istio_ambient.sh — install Istio ambient mesh on an app cluster via ArgoCD

function deploy_istio_ambient() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: [APP_CLUSTER_NAME=<ctx>] [ARGOCD_CONTEXT=<hub-ctx>] ./scripts/k3d-manager deploy_istio_ambient

Applies the istio-ambient ApplicationSet to the hub ArgoCD (ARGOCD_CONTEXT, default
k3d-k3d-cluster), targeting APP_CLUSTER_NAME (default ubuntu-k3s). Preconditions:
  - The target cluster is registered with the hub ArgoCD (register_app_cluster).
  - The target cluster's CNI is Cilium with cni.exclusive=false (deploy with K3S_AMBIENT_MESH=true).
  - The platform AppProject permits istio-system as a destination for the target cluster.
HELP
    return 0
  fi

  local _appset="${SCRIPT_DIR}/etc/argocd/applicationsets/istio-ambient.yaml"
  : "${ARGOCD_NAMESPACE:=cicd}"
  : "${ARGOCD_CONTEXT:=k3d-k3d-cluster}"
  : "${APP_CLUSTER_NAME:=${ARGOCD_APP_CLUSTER_NAME:-ubuntu-k3s}}"
  : "${AMBIENT_ISTIO_VERSION:=1.24.2}"
  export ARGOCD_NAMESPACE APP_CLUSTER_NAME AMBIENT_ISTIO_VERSION

  if [[ ! -f "${_appset}" ]]; then
    _err "[istio_ambient] ApplicationSet not found: ${_appset}"
    return 1
  fi

  _info "[istio_ambient] Applying istio-ambient ApplicationSet (hub: ${ARGOCD_CONTEXT}, target: ${APP_CLUSTER_NAME})..."
  # shellcheck disable=SC2016
  if envsubst '$ARGOCD_NAMESPACE $APP_CLUSTER_NAME $AMBIENT_ISTIO_VERSION' < "${_appset}" \
      | _kubectl apply --context "${ARGOCD_CONTEXT}" -f -; then
    _info "[istio_ambient] Applied — ArgoCD will sync istio-system on ${APP_CLUSTER_NAME}"
  else
    _err "[istio_ambient] Failed to apply istio-ambient ApplicationSet"
    return 1
  fi
}
