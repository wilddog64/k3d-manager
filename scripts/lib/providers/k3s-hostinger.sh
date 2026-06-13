#!/usr/bin/env bash
# scripts/lib/providers/k3s-hostinger.sh
# Single-node k3s app cluster on a pre-existing, permanent Hostinger VPS (SSH target).
# The VPS is provisioned out-of-band (Hostinger panel); this provider never creates or
# deletes the VM — it only installs/uninstalls k3s over SSH and registers the context.

_HOSTINGER_SSH_USER="${HOSTINGER_SSH_USER:-ubuntu}"
_HOSTINGER_SSH_KEY="${HOSTINGER_SSH_KEY:-${HOME}/.ssh/hostinger}"
_HOSTINGER_KUBE_CONTEXT="ubuntu-hostinger"
_HOSTINGER_KUBECONFIG="${HOME}/.kube/hostinger.config"

function _hostinger_require_host() {
  local host="${HOSTINGER_HOST:-}"
  if [[ -z "${host}" ]]; then
    printf 'ERROR: %s\n' "[k3s-hostinger] HOSTINGER_HOST is not set — export HOSTINGER_HOST=<vps-ip>" >&2
    return 1
  fi
  printf '%s' "${host}"
}

function _hostinger_wait_for_ssh() {
  local host="$1" ssh_user="$2" ssh_key="$3"
  _info "[k3s-hostinger] Waiting for SSH on ${ssh_user}@${host}..."
  local attempts=0
  until ssh -i "${ssh_key}" -o BatchMode=yes -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=accept-new \
        "${ssh_user}@${host}" 'true' >/dev/null 2>&1; do
    (( ++attempts ))
    if (( attempts >= 12 )); then
      printf 'ERROR: %s\n' "[k3s-hostinger] SSH not ready after 120s on ${host}" >&2
      return 1
    fi
    sleep 10
  done
}

function _hostinger_k3sup_install() {
  local host="$1" ssh_user="$2" ssh_key="$3"
  _ensure_k3sup
  mkdir -p "$(dirname "${_HOSTINGER_KUBECONFIG}")" "${HOME}/.kube"
  _info "[k3s-hostinger] Installing k3s on ${ssh_user}@${host} via k3sup..."
  _run_command -- k3sup install \
    --ip "${host}" \
    --user "${ssh_user}" \
    --ssh-key "${ssh_key}" \
    --local-path "${_HOSTINGER_KUBECONFIG}" \
    --context "${_HOSTINGER_KUBE_CONTEXT}" \
    --k3s-extra-args '--disable traefik --disable servicelb'
}

function _hostinger_merge_kubeconfig() {
  local tmp_kube tmp_merged
  tmp_kube="${HOME}/.kube/ubuntu-hostinger.tmp"
  tmp_merged="${HOME}/.kube/config.tmp"
  if kubectl config get-contexts "${_HOSTINGER_KUBE_CONTEXT}" >/dev/null 2>&1; then
    kubectl config delete-context "${_HOSTINGER_KUBE_CONTEXT}" >/dev/null 2>&1 || true
    _info "[k3s-hostinger] Removed stale ${_HOSTINGER_KUBE_CONTEXT} context"
  fi
  cp "${_HOSTINGER_KUBECONFIG}" "${tmp_kube}"
  chmod 600 "${tmp_kube}"
  KUBECONFIG="${tmp_kube}:${HOME}/.kube/config" kubectl config view --flatten > "${tmp_merged}"
  mv "${tmp_merged}" "${HOME}/.kube/config"
  chmod 600 "${HOME}/.kube/config"
  rm -f "${tmp_kube}"
  _info "[k3s-hostinger] ${_HOSTINGER_KUBE_CONTEXT} context merged into ~/.kube/config"
}

function _provider_k3s_hostinger_deploy_cluster() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: CLUSTER_PROVIDER=k3s-hostinger ./scripts/k3d-manager deploy_cluster

Install a single-node k3s app cluster on a pre-existing Hostinger VPS:
  1. SSH ready wait     — up to 120s
  2. k3sup install      — install k3s; merge kubeconfig as ubuntu-hostinger
  3. kubectl wait       — node Ready

The VPS is provisioned out-of-band (Hostinger panel) and is permanent; this
provider never creates or deletes the VM.

Config (env overrides):
  HOSTINGER_HOST       VPS public IP (REQUIRED)
  HOSTINGER_SSH_USER   SSH user (default: ubuntu)
  HOSTINGER_SSH_KEY    SSH private key path (default: ~/.ssh/hostinger)
HELP
    return 0
  fi

  local host ssh_user ssh_key
  host="$(_hostinger_require_host)" || return 1
  ssh_user="${_HOSTINGER_SSH_USER}"
  ssh_key="${_HOSTINGER_SSH_KEY}"

  if [[ ! -f "${ssh_key}" ]]; then
    printf 'ERROR: %s\n' "[k3s-hostinger] SSH key not found: ${ssh_key}" >&2
    return 1
  fi

  _hostinger_wait_for_ssh "${host}" "${ssh_user}" "${ssh_key}" || return 1
  _hostinger_k3sup_install "${host}" "${ssh_user}" "${ssh_key}" || return 1
  _hostinger_merge_kubeconfig || return 1

  _info "[k3s-hostinger] Waiting for node to be Ready..."
  local attempts=0
  until KUBECONFIG="${_HOSTINGER_KUBECONFIG}" kubectl get nodes 2>/dev/null | grep -q " Ready"; do
    (( ++attempts ))
    if (( attempts >= 60 )); then
      printf 'ERROR: %s\n' "[k3s-hostinger] Node did not become Ready after 300s" >&2
      return 1
    fi
    sleep 5
  done

  _info "[k3s-hostinger] Labeling node..."
  local node_name
  node_name=$(KUBECONFIG="${_HOSTINGER_KUBECONFIG}" kubectl get nodes \
    --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -n1)
  [[ -n "${node_name}" ]] && \
    KUBECONFIG="${_HOSTINGER_KUBECONFIG}" kubectl label node "${node_name}" \
      k3d-manager/node-type=server --overwrite >/dev/null 2>&1 || true

  _info "[k3s-hostinger] Cluster ready."
  _info "[k3s-hostinger] Verify: kubectl --context ${_HOSTINGER_KUBE_CONTEXT} get nodes"
}

function _provider_k3s_hostinger_destroy_cluster() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: CLUSTER_PROVIDER=k3s-hostinger ./scripts/k3d-manager destroy_cluster --confirm

Uninstall k3s from the Hostinger VPS (the VM is permanent and is NOT deleted):
  1. Run k3s-uninstall.sh on the box via SSH
  2. Remove ubuntu-hostinger kubeconfig context
HELP
    return 0
  fi

  if [[ "${1:-}" != "--confirm" ]]; then
    printf 'ERROR: %s\n' "[k3s-hostinger] destroy_cluster requires --confirm" >&2
    return 1
  fi

  local host ssh_user ssh_key
  host="$(_hostinger_require_host)" || return 1
  ssh_user="${_HOSTINGER_SSH_USER}"
  ssh_key="${_HOSTINGER_SSH_KEY}"

  _info "[k3s-hostinger] Uninstalling k3s on ${ssh_user}@${host}..."
  _run_command -- ssh -i "${ssh_key}" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "${ssh_user}@${host}" 'sudo /usr/local/bin/k3s-uninstall.sh' 2>/dev/null || \
    _info "[k3s-hostinger] k3s-uninstall.sh not present — skipping"

  if kubectl config get-contexts "${_HOSTINGER_KUBE_CONTEXT}" >/dev/null 2>&1; then
    kubectl config delete-context "${_HOSTINGER_KUBE_CONTEXT}" >/dev/null 2>&1 || true
    _info "[k3s-hostinger] Removed kubeconfig context ${_HOSTINGER_KUBE_CONTEXT}"
  fi

  rm -f "${_HOSTINGER_KUBECONFIG}"
  _info "[k3s-hostinger] k3s uninstalled; VPS preserved."
}
