#!/usr/bin/env bash
set -euo pipefail

function add_ubuntu_k3s_cluster() {
  local ssh_host="${UBUNTU_K3S_SSH_HOST:-ubuntu}"
  local ssh_user="${UBUNTU_K3S_SSH_USER:-parallels}"
  local external_ip="${UBUNTU_K3S_EXTERNAL_IP:-${ssh_host}}"
  local remote_kubeconfig="${UBUNTU_K3S_REMOTE_KUBECONFIG:-/home/${ssh_user}/.kube/k3s.yaml}"
  local local_kubeconfig="${UBUNTU_K3S_LOCAL_KUBECONFIG:-${HOME}/.kube/k3s-ubuntu.yaml}"
  local ssh_target="${ssh_user}@${ssh_host}"

  case "${remote_kubeconfig}" in
    (*[!A-Za-z0-9_./-]*)
      _err "[shopping_cart] Unsafe characters in UBUNTU_K3S_REMOTE_KUBECONFIG: ${remote_kubeconfig}"
      return 1
      ;;
  esac

  _info "[shopping_cart] Exporting Ubuntu k3s kubeconfig from ${ssh_target}"
  mkdir -p "$(dirname "${local_kubeconfig}")"

# shellcheck disable=SC2029
  if ! ssh "${ssh_target}" "cat ${remote_kubeconfig}" 2>/dev/null \
      | sed "s|127.0.0.1|${external_ip}|g" > "${local_kubeconfig}"; then
    _err "[shopping_cart] Failed to export kubeconfig from ${ssh_target}:${remote_kubeconfig}"
    _err "[shopping_cart] Ensure ${ssh_user} can read ${remote_kubeconfig} on ${ssh_host}"
    return 1
  fi
  chmod 600 "${local_kubeconfig}"

  _info "[shopping_cart] Verifying connectivity to Ubuntu k3s at ${external_ip}:6443"
  if ! KUBECONFIG="${local_kubeconfig}" _run_command -- kubectl get nodes; then
    _err "[shopping_cart] Cannot reach Ubuntu k3s API at ${external_ip}:6443"
    return 1
  fi

  _info "[shopping_cart] Merging ubuntu-k3s context into ~/.kube/config"
  if ! kubectl config get-contexts ubuntu-k3s &>/dev/null; then
    local _tmp_kube _tmp_merged
    _tmp_kube="${HOME}/.kube/ubuntu-k3s-tmp.yaml"
    _tmp_merged="${HOME}/.kube/config-merged-tmp.yaml"
    cp "${local_kubeconfig}" "${_tmp_kube}"
    chmod 600 "${_tmp_kube}"
    local _src_context
    if ! _src_context=$(KUBECONFIG="${_tmp_kube}" kubectl config current-context 2>/dev/null); then
      _src_context=""
    fi
    if [[ -n "${_src_context}" && "${_src_context}" != "ubuntu-k3s" ]]; then
      KUBECONFIG="${_tmp_kube}" kubectl config rename-context "${_src_context}" ubuntu-k3s
    fi
    KUBECONFIG="${HOME}/.kube/config:${_tmp_kube}" kubectl config view --flatten > "${_tmp_merged}"
    mv "${_tmp_merged}" "${HOME}/.kube/config"
    chmod 600 "${HOME}/.kube/config"
    rm -f "${_tmp_kube}"
    _info "[shopping_cart] ubuntu-k3s context merged into ~/.kube/config"
  else
    _info "[shopping_cart] Context 'ubuntu-k3s' already present in ~/.kube/config — skipping merge"
  fi

  local kube_context
  if [[ -n "${UBUNTU_K3S_CONTEXT:-}" ]]; then
    kube_context="${UBUNTU_K3S_CONTEXT}"
  else
    if ! kube_context=$(KUBECONFIG="${local_kubeconfig}" kubectl config current-context 2>/dev/null); then
      _err "[shopping_cart] Failed to determine current context from ${local_kubeconfig}"
      return 1
    fi
    if [[ -z "${kube_context}" ]]; then
      _err "[shopping_cart] kubeconfig ${local_kubeconfig} has no current-context configured"
      return 1
    fi
  fi

  _info "[shopping_cart] Registering Ubuntu k3s cluster with ArgoCD using context ${kube_context}"
  KUBECONFIG="${local_kubeconfig}" _run_command -- argocd cluster add "${kube_context}" \
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
