#!/usr/bin/env bash
set -euo pipefail

function add_ubuntu_k3s_cluster() {
  local kubeconfig="${UBUNTU_K3S_KUBECONFIG:-${HOME}/.kube/k3s-ubuntu.yaml}"

  if [[ ! -f "$kubeconfig" ]]; then
    _err "[shopping_cart] Ubuntu k3s kubeconfig not found: ${kubeconfig}"
    _err "[shopping_cart] Run: scp ubuntu:/tmp/k3s-external.yaml ${kubeconfig}"
    return 1
  fi

  _info "[shopping_cart] Registering Ubuntu k3s cluster with ArgoCD"
  KUBECONFIG="$kubeconfig" _run_command -- argocd cluster add k3s-automation \
    --name ubuntu-k3s \
    --kubeconfig "$kubeconfig"
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
