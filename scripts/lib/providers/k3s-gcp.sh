# shellcheck shell=bash
# scripts/lib/providers/k3s-gcp.sh — k3s on ACG GCP sandbox (single-node)
#
# Provider actions:
#   deploy_cluster  — firewall → GCE instance → k3sup install → kubeconfig merge
#   destroy_cluster — delete instance → delete firewall rule → remove kubeconfig context
#
# Config (env overrides):
#   GCP_PROJECT   GCP project ID (exported by gcp_get_credentials)
#   GCP_ZONE      GCE zone (default: us-west1-a)
#   GCP_SSH_KEY   Path to SSH private key (default: ~/.ssh/k3d-manager-gcp-key)
#   GCP_SSH_USER  SSH user on the instance (default: ubuntu)

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/gcp.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/shopping_cart.sh"

_GCP_INSTANCE_NAME="k3d-manager-gcp-node"
_GCP_FIREWALL_RULE="k3d-manager-k3s-api"
_GCP_MACHINE_TYPE="e2-standard-2"
_GCP_IMAGE_FAMILY="ubuntu-2204-lts"
_GCP_IMAGE_PROJECT="ubuntu-os-cloud"
_GCP_NETWORK_TAG="k3d-manager"
_GCP_KUBECONFIG="${HOME}/.kube/k3s-gcp.yaml"
_GCP_KUBE_CONTEXT="ubuntu-gcp"
_GCP_SSH_CONFIG_HOST="ubuntu-gcp"

function _gcp_zone() {
  printf '%s' "${GCP_ZONE:-us-west1-a}"
}

function _gcp_ssh_key() {
  printf '%s' "${GCP_SSH_KEY:-${HOME}/.ssh/k3d-manager-gcp-key}"
}

function _gcp_ssh_user() {
  printf '%s' "${GCP_SSH_USER:-ubuntu}"
}

function _gcp_ensure_firewall() {
  local project="$1"
  if gcloud compute firewall-rules describe "${_GCP_FIREWALL_RULE}" \
      --project="${project}" --quiet >/dev/null 2>&1; then
    _info "[k3s-gcp] Firewall rule ${_GCP_FIREWALL_RULE} already exists — skipping"
    return 0
  fi
  _info "[k3s-gcp] Creating firewall rule ${_GCP_FIREWALL_RULE} (TCP 6443)..."
  gcloud compute firewall-rules create "${_GCP_FIREWALL_RULE}" \
    --project="${project}" \
    --allow=tcp:6443 \
    --target-tags="${_GCP_NETWORK_TAG}" \
    --description="k3d-manager: k3s API server access" \
    --quiet
}

function _gcp_create_instance() {
  local project="$1" zone="$2" ssh_user="$3" ssh_key_pub="$4"
  _info "[k3s-gcp] Creating instance ${_GCP_INSTANCE_NAME} in ${zone}..."
  gcloud compute instances create "${_GCP_INSTANCE_NAME}" \
    --project="${project}" \
    --zone="${zone}" \
    --machine-type="${_GCP_MACHINE_TYPE}" \
    --image-family="${_GCP_IMAGE_FAMILY}" \
    --image-project="${_GCP_IMAGE_PROJECT}" \
    --tags="${_GCP_NETWORK_TAG}" \
    --metadata="ssh-keys=${ssh_user}:$(cat "${ssh_key_pub}")" \
    --quiet
}

function _gcp_get_external_ip() {
  local project="$1" zone="$2"
  gcloud compute instances describe "${_GCP_INSTANCE_NAME}" \
    --project="${project}" \
    --zone="${zone}" \
    --format="value(networkInterfaces[0].accessConfigs[0].natIP)"
}

function _gcp_update_ssh_config() {
  local external_ip="$1" ssh_user="$2" ssh_key="$3"
  local ssh_config="${HOME}/.ssh/config"
  # Remove any existing ubuntu-gcp block
  if grep -q "^Host ${_GCP_SSH_CONFIG_HOST}$" "${ssh_config}" 2>/dev/null; then
    local tmp
    tmp=$(mktemp)
    awk "/^Host ${_GCP_SSH_CONFIG_HOST}$/{found=1} found && /^Host / && !/^Host ${_GCP_SSH_CONFIG_HOST}$/{found=0} !found{print}" \
      "${ssh_config}" > "${tmp}"
    mv "${tmp}" "${ssh_config}"
    chmod 600 "${ssh_config}"
  fi
  cat >> "${ssh_config}" <<EOF

Host ${_GCP_SSH_CONFIG_HOST}
  HostName ${external_ip}
  User ${ssh_user}
  IdentityFile ${ssh_key}
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
EOF
  _info "[k3s-gcp] SSH config updated: Host ${_GCP_SSH_CONFIG_HOST} → ${external_ip}"
}

function _gcp_wait_for_ssh() {
  local external_ip="$1" ssh_user="$2" ssh_key="$3"
  _info "[k3s-gcp] Waiting for SSH on ${external_ip} (up to 120s)..."
  local attempts=0
  until ssh -i "${ssh_key}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 "${ssh_user}@${external_ip}" true 2>/dev/null; do
    (( attempts++ ))
    if (( attempts >= 24 )); then
      printf 'ERROR: %s\n' "[k3s-gcp] SSH not ready after 120s" >&2
      return 1
    fi
    sleep 5
  done
  _info "[k3s-gcp] SSH ready."
}

function _gcp_k3sup_install() {
  local external_ip="$1" ssh_user="$2" ssh_key="$3"
  _ensure_k3sup
  mkdir -p "$(dirname "${_GCP_KUBECONFIG}")" "${HOME}/.kube"
  _info "[k3s-gcp] Installing k3s on ${ssh_user}@${external_ip} via k3sup..."
  _run_command -- k3sup install \
    --ip "${external_ip}" \
    --user "${ssh_user}" \
    --ssh-key "${ssh_key}" \
    --local-path "${_GCP_KUBECONFIG}" \
    --context "${_GCP_KUBE_CONTEXT}" \
    --k3s-extra-args '--disable traefik --disable servicelb'
}

function _gcp_merge_kubeconfig() {
  local tmp_kube tmp_merged
  tmp_kube="${HOME}/.kube/ubuntu-gcp.tmp"
  tmp_merged="${HOME}/.kube/config.tmp"
  if kubectl config get-contexts "${_GCP_KUBE_CONTEXT}" >/dev/null 2>&1; then
    kubectl config delete-context "${_GCP_KUBE_CONTEXT}" >/dev/null 2>&1 || true
    _info "[k3s-gcp] Removed stale ${_GCP_KUBE_CONTEXT} context"
  fi
  cp "${_GCP_KUBECONFIG}" "${tmp_kube}"
  chmod 600 "${tmp_kube}"
  KUBECONFIG="${tmp_kube}:${HOME}/.kube/config" kubectl config view --flatten > "${tmp_merged}"
  mv "${tmp_merged}" "${HOME}/.kube/config"
  chmod 600 "${HOME}/.kube/config"
  rm -f "${tmp_kube}"
  _info "[k3s-gcp] ${_GCP_KUBE_CONTEXT} context merged into ~/.kube/config"
}

function _provider_k3s_gcp_deploy_cluster() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: CLUSTER_PROVIDER=k3s-gcp ./scripts/k3d-manager deploy_cluster

Provision a single-node k3s cluster on ACG GCP sandbox:
  1. gcloud firewall-rules create  — open TCP 6443
  2. gcloud instances create       — e2-standard-2, Ubuntu 20.04, us-west1-a
  3. SSH ready wait                — up to 120s
  4. k3sup install                 — install k3s; merge kubeconfig as ubuntu-gcp
  5. kubectl wait                  — node Ready

Config (env overrides):
  GCP_PROJECT   GCP project ID (required — set by gcp_get_credentials)
  GCP_ZONE      GCE zone (default: us-west1-a)
  GCP_SSH_KEY   SSH private key (default: ~/.ssh/k3d-manager-gcp-key)
  GCP_SSH_USER  SSH user (default: ubuntu)
HELP
    return 0
  fi

  local project="${GCP_PROJECT:-}"
  if [[ -z "${project}" ]]; then
    printf 'ERROR: %s\n' "[k3s-gcp] GCP_PROJECT is not set — run gcp_get_credentials first" >&2
    return 1
  fi

  local zone ssh_key ssh_user
  zone="$(_gcp_zone)"
  ssh_key="$(_gcp_ssh_key)"
  ssh_user="$(_gcp_ssh_user)"
  local ssh_key_pub="${ssh_key}.pub"

  if [[ ! -f "${ssh_key}" ]]; then
    printf 'ERROR: %s\n' "[k3s-gcp] SSH key not found: ${ssh_key}" >&2
    return 1
  fi
  if [[ ! -f "${ssh_key_pub}" ]]; then
    printf 'ERROR: %s\n' "[k3s-gcp] SSH public key not found: ${ssh_key_pub}" >&2
    return 1
  fi

  _gcp_ensure_firewall "${project}" || return 1
  _gcp_create_instance "${project}" "${zone}" "${ssh_user}" "${ssh_key_pub}" || return 1

  local external_ip
  external_ip="$(_gcp_get_external_ip "${project}" "${zone}")"
  if [[ -z "${external_ip}" ]]; then
    printf 'ERROR: %s\n' "[k3s-gcp] Could not get external IP for ${_GCP_INSTANCE_NAME}" >&2
    return 1
  fi
  _info "[k3s-gcp] Instance IP: ${external_ip}"

  _gcp_update_ssh_config "${external_ip}" "${ssh_user}" "${ssh_key}" || return 1
  _gcp_wait_for_ssh "${external_ip}" "${ssh_user}" "${ssh_key}" || return 1
  _gcp_k3sup_install "${external_ip}" "${ssh_user}" "${ssh_key}" || return 1
  _gcp_merge_kubeconfig || return 1

  _info "[k3s-gcp] Waiting for node to be Ready..."
  local attempts=0
  until KUBECONFIG="${_GCP_KUBECONFIG}" kubectl get nodes 2>/dev/null | grep -q " Ready"; do
    (( attempts++ ))
    if (( attempts >= 60 )); then
      printf 'ERROR: %s\n' "[k3s-gcp] Node did not become Ready after 300s" >&2
      return 1
    fi
    sleep 5
  done

  _info "[k3s-gcp] Labeling node..."
  local node_name
  node_name=$(KUBECONFIG="${_GCP_KUBECONFIG}" kubectl get nodes \
    --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -n1)
  [[ -n "${node_name}" ]] && \
    KUBECONFIG="${_GCP_KUBECONFIG}" kubectl label node "${node_name}" \
      k3d-manager/node-type=server --overwrite >/dev/null 2>&1 || true

  _info "[k3s-gcp] Cluster ready."
  _info "[k3s-gcp] Verify: kubectl --context ${_GCP_KUBE_CONTEXT} get nodes"
}

function _provider_k3s_gcp_destroy_cluster() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: CLUSTER_PROVIDER=k3s-gcp ./scripts/k3d-manager destroy_cluster --confirm

Tear down the GCP k3s cluster:
  1. Delete GCE instance
  2. Delete firewall rule
  3. Remove ubuntu-gcp SSH config entry
  4. Remove ubuntu-gcp kubeconfig context
HELP
    return 0
  fi

  if [[ "${1:-}" != "--confirm" ]]; then
    printf 'ERROR: %s\n' "[k3s-gcp] destroy_cluster requires --confirm" >&2
    return 1
  fi

  local project="${GCP_PROJECT:-}"
  if [[ -z "${project}" ]]; then
    printf 'ERROR: %s\n' "[k3s-gcp] GCP_PROJECT is not set" >&2
    return 1
  fi

  local zone
  zone="$(_gcp_zone)"

  _info "[k3s-gcp] Deleting instance ${_GCP_INSTANCE_NAME}..."
  gcloud compute instances delete "${_GCP_INSTANCE_NAME}" \
    --project="${project}" \
    --zone="${zone}" \
    --quiet 2>/dev/null || \
    _info "[k3s-gcp] Instance not found — skipping"

  _info "[k3s-gcp] Deleting firewall rule ${_GCP_FIREWALL_RULE}..."
  gcloud compute firewall-rules delete "${_GCP_FIREWALL_RULE}" \
    --project="${project}" \
    --quiet 2>/dev/null || \
    _info "[k3s-gcp] Firewall rule not found — skipping"

  # Remove SSH config entry
  local ssh_config="${HOME}/.ssh/config"
  if grep -q "^Host ${_GCP_SSH_CONFIG_HOST}$" "${ssh_config}" 2>/dev/null; then
    local tmp
    tmp=$(mktemp)
    awk "/^Host ${_GCP_SSH_CONFIG_HOST}$/{found=1} found && /^Host / && !/^Host ${_GCP_SSH_CONFIG_HOST}$/{found=0} !found{print}" \
      "${ssh_config}" > "${tmp}"
    mv "${tmp}" "${ssh_config}"
    chmod 600 "${ssh_config}"
    _info "[k3s-gcp] Removed SSH config entry for ${_GCP_SSH_CONFIG_HOST}"
  fi

  # Remove kubeconfig context
  if kubectl config get-contexts "${_GCP_KUBE_CONTEXT}" >/dev/null 2>&1; then
    kubectl config delete-context "${_GCP_KUBE_CONTEXT}" >/dev/null 2>&1 || true
    _info "[k3s-gcp] Removed kubeconfig context ${_GCP_KUBE_CONTEXT}"
  fi

  _info "[k3s-gcp] GCP cluster destroyed."
}
