#!/usr/bin/env bash
# scripts/plugins/observability.sh

function deploy_observability() {
  _info "[observability] Deploying Hub observability stack..."
  local _appset="${SCRIPT_DIR}/etc/argocd/applicationsets/observability.yaml"
  : "${ARGOCD_NAMESPACE:=cicd}"
  K3D_MANAGER_BRANCH="${K3D_MANAGER_BRANCH:-$(git -C "${SCRIPT_DIR}/.." rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"
  export K3D_MANAGER_BRANCH ARGOCD_NAMESPACE
  # shellcheck disable=SC2016
  if envsubst '$ARGOCD_NAMESPACE $K3D_MANAGER_BRANCH' < "${_appset}" | _kubectl apply -f -; then
    _info "[observability] Hub ApplicationSet applied — ArgoCD will sync monitoring/trivy-system"
  else
    _err "[observability] Failed to apply Hub observability ApplicationSet"
    return 1
  fi

  local _istio_manifest="${SCRIPT_DIR}/etc/observability/istio.yaml"
  if [[ -f "${_istio_manifest}" ]]; then
    _kubectl apply -f "${_istio_manifest}" >/dev/null \
      && _info "[observability] Istio Gateway + VirtualServices applied (prometheus/grafana.shopping-cart.local)"
  fi
}

function deploy_observability_acg() {
  _info "[observability] Deploying ACG observability stack..."
  local _appset="${SCRIPT_DIR}/etc/argocd/applicationsets/observability-acg.yaml"
  : "${ARGOCD_NAMESPACE:=cicd}"
  K3D_MANAGER_BRANCH="${K3D_MANAGER_BRANCH:-$(git -C "${SCRIPT_DIR}/.." rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"
  export K3D_MANAGER_BRANCH ARGOCD_NAMESPACE
  # shellcheck disable=SC2016
  if envsubst '$ARGOCD_NAMESPACE $K3D_MANAGER_BRANCH' < "${_appset}" | _kubectl apply -f -; then
    _info "[observability] ACG ApplicationSet applied — ArgoCD will sync monitoring/trivy-system on ubuntu-k3s"
  else
    _err "[observability] Failed to apply ACG observability ApplicationSet"
    return 1
  fi
}

function observability_status() {
  _info "[observability] === Hub (k3d-cluster) ==="
  for _ns in monitoring trivy-system; do
    _info "[observability] --- ${_ns} ---"
    _kubectl get pods -n "${_ns}" --no-headers 2>/dev/null || true
  done
  _info "[observability] === ACG (ubuntu-k3s) ==="
  for _ns in monitoring trivy-system; do
    _info "[observability] --- ${_ns} ---"
    kubectl get pods -n "${_ns}" --context ubuntu-k3s --no-headers 2>/dev/null || true
  done
}

function trivy_scan_report() {
  _info "[observability] VulnerabilityReport summary — Hub:"
  _kubectl get vulnerabilityreports -A --no-headers 2>/dev/null \
    | awk '{print $1, $2, $6, $7, $8}' | column -t | sort -k4 -rn || true
  _info "[observability] VulnerabilityReport summary — ACG:"
  kubectl get vulnerabilityreports -A --context ubuntu-k3s --no-headers 2>/dev/null \
    | awk '{print $1, $2, $6, $7, $8}' | column -t | sort -k4 -rn || true
}
