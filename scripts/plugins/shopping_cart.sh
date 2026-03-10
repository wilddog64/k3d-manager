#!/usr/bin/env bash
set -euo pipefail

function add_ubuntu_k3s_cluster() {
  local ssh_host="${UBUNTU_K3S_SSH_HOST:-ubuntu}"
  local ssh_user="${UBUNTU_K3S_SSH_USER:-parallels}"
  local external_ip="${UBUNTU_K3S_EXTERNAL_IP:-10.211.55.14}"
  local remote_kubeconfig="${UBUNTU_K3S_REMOTE_KUBECONFIG:-/home/${ssh_user}/.kube/k3s.yaml}"
  local local_kubeconfig="${UBUNTU_K3S_LOCAL_KUBECONFIG:-${HOME}/.kube/k3s-ubuntu.yaml}"

  _info "[shopping_cart] Exporting Ubuntu k3s kubeconfig from ${ssh_host}"
  mkdir -p "$(dirname "${local_kubeconfig}")"

# shellcheck disable=SC2029
  if ! ssh "${ssh_host}" "cat ${remote_kubeconfig}" 2>/dev/null \
      | sed "s|127.0.0.1|${external_ip}|g" > "${local_kubeconfig}"; then
    _err "[shopping_cart] Failed to export kubeconfig from ${ssh_host}:${remote_kubeconfig}"
    _err "[shopping_cart] Ensure ${ssh_user} can read ${remote_kubeconfig} on ${ssh_host}"
    return 1
  fi
  chmod 600 "${local_kubeconfig}"

  _info "[shopping_cart] Verifying connectivity to Ubuntu k3s at ${external_ip}:6443"
  if ! KUBECONFIG="${local_kubeconfig}" _run_command -- kubectl get nodes; then
    _err "[shopping_cart] Cannot reach Ubuntu k3s API at ${external_ip}:6443"
    return 1
  fi

  _info "[shopping_cart] Registering Ubuntu k3s cluster with ArgoCD"
  KUBECONFIG="${local_kubeconfig}" _run_command -- argocd cluster add k3s-automation \
    --name ubuntu-k3s \
    --kubeconfig "${local_kubeconfig}"
}

function register_shopping_cart_apps() {
  local repo_root
  if ! repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
    _err "[shopping_cart] Unable to determine repository root"
    return 1
  fi

  local argocd_dir
  argocd_dir="${repo_root}/../shopping-carts/shopping-cart-infra/argocd/applications"

  if [[ ! -d "$argocd_dir" ]]; then
    _err "[shopping_cart] shopping-cart-infra applications not found: ${argocd_dir}"
    _err "[shopping_cart] Clone shopping-cart-infra under ../shopping-carts/"
    return 1
  fi

  _info "[shopping_cart] Applying ArgoCD applications from ${argocd_dir}"
  _run_command -- kubectl apply -f "${argocd_dir}/"
}
