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
  local _tmp_kube _tmp_merged
  _tmp_kube="${HOME}/.kube/ubuntu-k3s-tmp.yaml"
  _tmp_merged="${HOME}/.kube/config-merged-tmp.yaml"
  if kubectl config get-contexts ubuntu-k3s &>/dev/null; then
    kubectl config delete-context ubuntu-k3s &>/dev/null || true
    _info "[shopping_cart] Removed stale ubuntu-k3s context — will re-merge with fresh credentials"
  fi
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

function _ensure_k3sup() {
  if _command_exist k3sup; then
    return 0
  fi
  _info "[shopping_cart] k3sup not found — installing..."
  if _command_exist brew; then
    _run_command --soft -- brew install k3sup
    if _command_exist k3sup; then
      return 0
    fi
  fi
  if _is_debian_family && _command_exist curl; then
    local _k3sup_installer
    _k3sup_installer="$(mktemp)"
    if ! curl -fsSL -o "${_k3sup_installer}" https://get.k3sup.dev; then
      rm -f "${_k3sup_installer}"
      _err "[shopping_cart] Failed to download k3sup installer from https://get.k3sup.dev"
    fi
    _run_command --soft --prefer-sudo -- sh "${_k3sup_installer}"
    rm -f "${_k3sup_installer}"
    if _command_exist k3sup; then
      return 0
    fi
  fi
  _err "[shopping_cart] k3sup not found and automatic installation failed — install manually: brew install k3sup"
}

function deploy_app_cluster() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: deploy_app_cluster [--confirm]

Install k3s on the remote EC2 app cluster via k3sup, then merge its kubeconfig
into ~/.kube/config as the ubuntu-k3s context.

Does NOT register the cluster with ArgoCD — that requires a bearer token:
  ssh ubuntu kubectl create token argocd-manager -n kube-system --duration=8760h
Then run: ./scripts/k3d-manager register_app_cluster

Config (override via env or scripts/etc/k3s/vars.sh):
  UBUNTU_K3S_SSH_HOST          SSH host alias (default: ubuntu)
  UBUNTU_K3S_SSH_USER          SSH user       (default: ubuntu)
  UBUNTU_K3S_EXTERNAL_IP       Node IP        (default: UBUNTU_K3S_SSH_HOST)
  UBUNTU_K3S_SSH_KEY           SSH key path   (default: ~/.ssh/k3d-manager-key.pem)
  UBUNTU_K3S_LOCAL_KUBECONFIG  Local kubeconfig path (default: ~/.kube/k3s-ubuntu.yaml)
HELP
    return 0
  fi

  if [[ "${1:-}" != "--confirm" ]]; then
    _err "[shopping_cart] deploy_app_cluster requires --confirm to prevent accidental runs"
    return 1
  fi

  local ssh_host="${UBUNTU_K3S_SSH_HOST:-ubuntu}"
  local ssh_user="${UBUNTU_K3S_SSH_USER:-ubuntu}"
  local external_ip="${UBUNTU_K3S_EXTERNAL_IP:-}"
  if [[ -z "$external_ip" ]]; then
    if _command_exist awk; then
      external_ip=$(awk "/^Host ${ssh_host}\$/{found=1} found && /HostName/{print \$2; exit}" \
        "${HOME}/.ssh/config" 2>/dev/null)
    fi
  fi
  : "${external_ip:=${ssh_host}}"
  local ssh_key="${UBUNTU_K3S_SSH_KEY:-${HOME}/.ssh/k3d-manager-key.pem}"
  local local_kubeconfig="${UBUNTU_K3S_LOCAL_KUBECONFIG:-${HOME}/.kube/k3s-ubuntu.yaml}"
  local kube_context="ubuntu-k3s"
  local kubeconfig_dir="${local_kubeconfig%/*}"

  _ensure_k3sup

  if [[ ! -f "${ssh_key}" ]]; then
    _err "[shopping_cart] SSH key not found: ${ssh_key}"
    return 1
  fi

  mkdir -p "${kubeconfig_dir}" "${HOME}/.kube"

  _info "[shopping_cart] Installing k3s on ${ssh_user}@${external_ip} via k3sup..."
  _run_command -- k3sup install \
    --ip "${external_ip}" \
    --user "${ssh_user}" \
    --ssh-key "${ssh_key}" \
    --local-path "${local_kubeconfig}" \
    --context "${kube_context}" \
    --k3s-extra-args '--disable traefik --disable servicelb'

  _info "[shopping_cart] Waiting for node to be Ready..."
  local attempts=0
  until KUBECONFIG="${local_kubeconfig}" kubectl get nodes 2>/dev/null | grep -q " Ready"; do
    (( attempts++ ))
    if (( attempts >= 30 )); then
      _err "[shopping_cart] Node did not become Ready after 150s"
      return 1
    fi
    sleep 5
  done
  _info "[shopping_cart] Node Ready."

  _info "[shopping_cart] Merging ubuntu-k3s context into ~/.kube/config"
  local tmp_kube tmp_merged
  tmp_kube="${HOME}/.kube/ubuntu-k3s.tmp"
  tmp_merged="${HOME}/.kube/config.tmp"
  if kubectl config get-contexts "${kube_context}" >/dev/null 2>&1; then
    kubectl config delete-context "${kube_context}" >/dev/null 2>&1 || true
    _info "[shopping_cart] Removed stale ${kube_context} context"
  fi
  cp "${local_kubeconfig}" "${tmp_kube}"
  chmod 600 "${tmp_kube}"
  KUBECONFIG="${tmp_kube}:${HOME}/.kube/config" kubectl config view --flatten > "${tmp_merged}"
  mv "${tmp_merged}" "${HOME}/.kube/config"
  chmod 600 "${HOME}/.kube/config"
  rm -f "${tmp_kube}"
  _info "[shopping_cart] ${kube_context} context merged into ~/.kube/config"

  _info "[shopping_cart] k3s install complete."
  _info ""
  _info "Next steps:"
  _info "  1. Get a bearer token:"
  _info "       ssh ${ssh_host} kubectl create token argocd-manager -n kube-system --duration=8760h"
  _info "  2. Register with ArgoCD:"
  _info "       ARGOCD_APP_CLUSTER_TOKEN=<token> ./scripts/k3d-manager register_app_cluster"
}
