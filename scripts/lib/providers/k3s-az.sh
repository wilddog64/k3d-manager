#!/usr/bin/env bash
# scripts/lib/providers/k3s-az.sh — k3s on ACG Azure sandbox (single-node)
#
# Provider actions:
#   deploy_cluster  — NSG rule → VM create → k3sup install → kubeconfig merge
#   destroy_cluster — delete VM → delete NSG rule → remove kubeconfig context

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/azure.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/shopping_cart.sh"

_AZ_VM_NAME="${AZ_VM_NAME:-k3d-azure-node}"
_AZ_VM_SIZE="${AZ_VM_SIZE:-Standard_B2s}"
_AZ_VM_IMAGE="${AZ_VM_IMAGE:-Ubuntu2204}"
_AZ_NSG_RULE_NAME="${AZ_NSG_RULE_NAME:-k3d-manager-k3s-api}"
_AZ_SSH_CONFIG_HOST="${AZ_SSH_CONFIG_HOST:-ubuntu-azure}"
_AZ_KUBE_CONTEXT="${AZ_KUBE_CONTEXT:-ubuntu-azure}"
_AZ_KUBECONFIG="${HOME}/.kube/k3s-az.yaml"

function _az_ssh_key() {
  printf '%s' "${AZ_SSH_KEY:-${HOME}/.ssh/k3d-manager-azure-key}"
}

function _az_ssh_user() {
  printf '%s' "${AZ_SSH_USER:-azureuser}"
}

function _az_resource_group() {
  printf '%s' "${AZ_RESOURCE_GROUP:-$(az group list --query '[0].name' -o tsv 2>/dev/null)}"
}

function _az_ensure_ssh_key() {
  local ssh_key
  ssh_key="$(_az_ssh_key)"
  if [[ ! -f "${ssh_key}" ]]; then
    _info "[k3s-az] Generating SSH key pair at ${ssh_key}..."
    ssh-keygen -t rsa -b 4096 -f "${ssh_key}" -N "" -q
    chmod 600 "${ssh_key}"
    chmod 644 "${ssh_key}.pub"
    _info "[k3s-az] SSH key pair created."
  fi
}

function _az_open_k3s_port() {
  local rg="$1"
  _info "[k3s-az] Opening TCP 6443 for k3s API on VM ${_AZ_VM_NAME}..."
  if az vm open-port \
      --port 6443 \
      --resource-group "${rg}" \
      --name "${_AZ_VM_NAME}" \
      --priority 1010 2>/dev/null; then
    _info "[k3s-az] NSG rule for port 6443 created."
  else
    _info "[k3s-az] Port 6443 rule may already exist — continuing."
  fi
}

function _az_create_vm() {
  local rg="$1" ssh_user="$2" ssh_key_pub="$3"
  if az vm show --resource-group "${rg}" --name "${_AZ_VM_NAME}" >/dev/null 2>&1; then
    _info "[k3s-az] VM ${_AZ_VM_NAME} already exists — skipping create."
    return 0
  fi
  _info "[k3s-az] Creating VM ${_AZ_VM_NAME} (${_AZ_VM_SIZE}, ${_AZ_VM_IMAGE}) in ${rg}..."
  az vm create \
    --resource-group "${rg}" \
    --name "${_AZ_VM_NAME}" \
    --image "${_AZ_VM_IMAGE}" \
    --size "${_AZ_VM_SIZE}" \
    --admin-username "${ssh_user}" \
    --ssh-key-values "${ssh_key_pub}" \
    --output none
}

function _az_get_public_ip() {
  local rg="$1"
  az vm show \
    --resource-group "${rg}" \
    --name "${_AZ_VM_NAME}" \
    --show-details \
    --query publicIps \
    --output tsv 2>/dev/null
}

function _az_update_ssh_config() {
  local external_ip="$1" ssh_user="$2" ssh_key="$3"
  local ssh_config="${HOME}/.ssh/config"
  if grep -q "^Host ${_AZ_SSH_CONFIG_HOST}$" "${ssh_config}" 2>/dev/null; then
    local tmp
    tmp=$(mktemp)
    awk "/^Host ${_AZ_SSH_CONFIG_HOST}$/{found=1} found && /^Host / && !/^Host ${_AZ_SSH_CONFIG_HOST}$/{found=0} !found{print}" \
      "${ssh_config}" > "${tmp}"
    mv "${tmp}" "${ssh_config}"
    chmod 600 "${ssh_config}"
  fi
  cat >> "${ssh_config}" <<EOF
Host ${_AZ_SSH_CONFIG_HOST}
  HostName ${external_ip}
  User ${ssh_user}
  IdentityFile ${ssh_key}
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
EOF
  _info "[k3s-az] SSH config updated: Host ${_AZ_SSH_CONFIG_HOST} → ${external_ip}"
}

function _az_wait_for_ssh() {
  local external_ip="$1" ssh_user="$2" ssh_key="$3"
  _info "[k3s-az] Waiting for SSH on ${external_ip} (up to 120s)..."
  local attempts=0
  until ssh -i "${ssh_key}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 "${ssh_user}@${external_ip}" true 2>/dev/null; do
    (( ++attempts ))
    if (( attempts >= 24 )); then
      printf 'ERROR: %s\n' "[k3s-az] SSH not ready after 120s" >&2
      return 1
    fi
    sleep 5
  done
  _info "[k3s-az] SSH ready."
}

function _az_k3sup_install() {
  local external_ip="$1" ssh_user="$2" ssh_key="$3"
  _ensure_k3sup
  mkdir -p "$(dirname "${_AZ_KUBECONFIG}")" "${HOME}/.kube"
  _info "[k3s-az] Installing k3s on ${ssh_user}@${external_ip} via k3sup..."
  _run_command -- k3sup install \
    --ip "${external_ip}" \
    --user "${ssh_user}" \
    --ssh-key "${ssh_key}" \
    --local-path "${_AZ_KUBECONFIG}" \
    --context "${_AZ_KUBE_CONTEXT}" \
    --k3s-extra-args '--disable traefik --disable servicelb'
}

function _az_merge_kubeconfig() {
  local tmp_kube tmp_merged
  tmp_kube="${HOME}/.kube/ubuntu-azure.tmp"
  tmp_merged="${HOME}/.kube/config.tmp"
  if kubectl config get-contexts "${_AZ_KUBE_CONTEXT}" >/dev/null 2>&1; then
    kubectl config delete-context "${_AZ_KUBE_CONTEXT}" >/dev/null 2>&1 || true
    _info "[k3s-az] Removed stale ${_AZ_KUBE_CONTEXT} context"
  fi
  cp "${_AZ_KUBECONFIG}" "${tmp_kube}"
  chmod 600 "${tmp_kube}"
  KUBECONFIG="${tmp_kube}:${HOME}/.kube/config" kubectl config view --flatten > "${tmp_merged}"
  mv "${tmp_merged}" "${HOME}/.kube/config"
  chmod 600 "${HOME}/.kube/config"
  rm -f "${tmp_kube}"
  _info "[k3s-az] ${_AZ_KUBE_CONTEXT} context merged into ~/.kube/config"
}

function _provider_k3s_az_deploy_cluster() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: CLUSTER_PROVIDER=k3s-az ./scripts/k3d-manager deploy_cluster

Provision a single-node k3s cluster on ACG Azure sandbox:
  1. az vm open-port 6443  — NSG rule for k3s API
  2. az vm create          — Standard_B2s, Ubuntu 22.04
  3. SSH ready wait        — up to 120s
  4. k3sup install         — install k3s; merge kubeconfig as ubuntu-azure
  5. kubectl wait          — node Ready

Pre-requisites:
  Run `az login` before deploy_cluster.
  SSH key: ~/.ssh/k3d-manager-azure-key (auto-generated if missing)

Config (env overrides):
  AZ_RESOURCE_GROUP   Resource group name (default: first group in subscription)
  AZ_VM_NAME          VM name (default: k3d-azure-node)
  AZ_VM_SIZE          VM size (default: Standard_B2s)
  AZ_VM_IMAGE         VM image (default: Ubuntu2204)
  AZ_SSH_KEY          SSH private key path (default: ~/.ssh/k3d-manager-azure-key)
  AZ_SSH_USER         SSH user (default: azureuser)
HELP
    return 0
  fi

  if ! _az_ok; then
    printf 'ERROR: %s\n' "[k3s-az] Not logged in to Azure — run: az login" >&2
    return 1
  fi

  local rg ssh_key ssh_user
  rg="$(_az_resource_group)"
  if [[ -z "${rg}" ]]; then
    printf 'ERROR: %s\n' "[k3s-az] Could not determine resource group — set AZ_RESOURCE_GROUP" >&2
    return 1
  fi
  _info "[k3s-az] Using resource group: ${rg}"

  ssh_key="$(_az_ssh_key)"
  ssh_user="$(_az_ssh_user)"
  local ssh_key_pub="${ssh_key}.pub"

  _az_ensure_ssh_key || return 1

  _az_create_vm "${rg}" "${ssh_user}" "${ssh_key_pub}" || return 1
  _az_open_k3s_port "${rg}" || return 1

  local external_ip
  external_ip="$(_az_get_public_ip "${rg}")"
  if [[ -z "${external_ip}" ]]; then
    printf 'ERROR: %s\n' "[k3s-az] Could not get public IP for VM ${_AZ_VM_NAME}" >&2
    return 1
  fi
  _info "[k3s-az] VM public IP: ${external_ip}"

  _az_update_ssh_config "${external_ip}" "${ssh_user}" "${ssh_key}" || return 1
  _az_wait_for_ssh "${external_ip}" "${ssh_user}" "${ssh_key}" || return 1
  _az_k3sup_install "${external_ip}" "${ssh_user}" "${ssh_key}" || return 1
  _az_merge_kubeconfig || return 1

  _info "[k3s-az] Waiting for node to be Ready..."
  local attempts=0
  until KUBECONFIG="${_AZ_KUBECONFIG}" kubectl get nodes 2>/dev/null | grep -q " Ready"; do
    (( ++attempts ))
    if (( attempts >= 60 )); then
      printf 'ERROR: %s\n' "[k3s-az] Node did not become Ready after 300s" >&2
      return 1
    fi
    sleep 5
  done

  _info "[k3s-az] Labeling node..."
  local node_name
  node_name=$(KUBECONFIG="${_AZ_KUBECONFIG}" kubectl get nodes \
    --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -n1)
  [[ -n "${node_name}" ]] && \
    KUBECONFIG="${_AZ_KUBECONFIG}" kubectl label node "${node_name}" \
      k3d-manager/node-type=server --overwrite >/dev/null 2>&1 || true

  _info "[k3s-az] Cluster ready."
  _info "[k3s-az] Verify: kubectl --context ${_AZ_KUBE_CONTEXT} get nodes"
}

function _provider_k3s_az_destroy_cluster() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: CLUSTER_PROVIDER=k3s-az ./scripts/k3d-manager destroy_cluster --confirm

Tear down the Azure k3s cluster:
  1. Delete VM
  2. Remove NSG open-port rule for 6443
  3. Remove ubuntu-azure SSH config entry
  4. Remove ubuntu-azure kubeconfig context
HELP
    return 0
  fi

  if [[ "${1:-}" != "--confirm" ]]; then
    printf 'ERROR: %s\n' "[k3s-az] destroy_cluster requires --confirm" >&2
    return 1
  fi

  if ! _az_ok; then
    printf 'ERROR: %s\n' "[k3s-az] Not logged in to Azure — run: az login" >&2
    return 1
  fi

  local rg
  rg="$(_az_resource_group)"
  if [[ -z "${rg}" ]]; then
    printf 'ERROR: %s\n' "[k3s-az] Could not determine resource group" >&2
    return 1
  fi

  _info "[k3s-az] Deleting VM ${_AZ_VM_NAME}..."
  az vm delete \
    --resource-group "${rg}" \
    --name "${_AZ_VM_NAME}" \
    --yes 2>/dev/null || \
    _info "[k3s-az] VM not found — skipping"

  # Remove SSH config entry
  local ssh_config="${HOME}/.ssh/config"
  if grep -q "^Host ${_AZ_SSH_CONFIG_HOST}$" "${ssh_config}" 2>/dev/null; then
    local tmp
    tmp=$(mktemp)
    awk "/^Host ${_AZ_SSH_CONFIG_HOST}$/{found=1} found && /^Host / && !/^Host ${_AZ_SSH_CONFIG_HOST}$/{found=0} !found{print}" \
      "${ssh_config}" > "${tmp}"
    mv "${tmp}" "${ssh_config}"
    chmod 600 "${ssh_config}"
    _info "[k3s-az] Removed SSH config entry for ${_AZ_SSH_CONFIG_HOST}"
  fi

  # Remove kubeconfig context
  if kubectl config get-contexts "${_AZ_KUBE_CONTEXT}" >/dev/null 2>&1; then
    kubectl config delete-context "${_AZ_KUBE_CONTEXT}" >/dev/null 2>&1 || true
    _info "[k3s-az] Removed kubeconfig context ${_AZ_KUBE_CONTEXT}"
  fi

  _info "[k3s-az] Azure cluster destroyed."
}
