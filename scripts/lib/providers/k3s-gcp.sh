# shellcheck shell=bash
# scripts/lib/providers/k3s-gcp.sh — k3s on Pluralsight ACG GCP sandbox (single-node)
#
# Provider actions:
#   deploy_cluster  — gcp_get_credentials → gcloud compute instance create
#                     → k3sup install → kubeconfig merge → kubectl label
#   destroy_cluster — gcloud compute instance delete
#
# Config (env overrides):
#   GCP_PROJECT       GCP project ID (from sandbox credentials)
#   GCP_ZONE          Compute zone (default: us-central1-a)
#   GCP_MACHINE_TYPE  Instance machine type (default: e2-medium)
#   GCP_INSTANCE_NAME VM instance name (default: k3s-gcp-server)
#   GCP_SSH_KEY_FILE  Path to SSH key for k3sup (default: ~/.ssh/k3d-manager-gcp-key)

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/gcp.sh"

_GCP_ZONE="${GCP_ZONE:-us-central1-a}"
_GCP_MACHINE_TYPE="${GCP_MACHINE_TYPE:-e2-medium}"
_GCP_INSTANCE_NAME="${GCP_INSTANCE_NAME:-k3s-gcp-server}"
_GCP_SSH_KEY_FILE="${GCP_SSH_KEY_FILE:-${HOME}/.ssh/k3d-manager-gcp-key}"
_GCP_KUBECONFIG="${HOME}/.kube/k3s-gcp.yaml"

function _provider_k3s_gcp_deploy_cluster() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: CLUSTER_PROVIDER=k3s-gcp ./scripts/k3d-manager deploy_cluster

Provision a single-node k3s cluster on ACG GCP sandbox:
  1. gcp_get_credentials        — extract GCP project + auth from Pluralsight UI
  2. gcloud auth activate       — configure gcloud with sandbox credentials
  3. gcloud compute create      — provision GCE instance
  4. k3sup install              — install k3s on the instance via SSH
  5. kubeconfig merge           — merge ~/.kube/k3s-gcp.yaml into default kubeconfig
  6. kubectl label              — k3d-manager/node-type=server

Milestone gate: kubectl --context k3s-gcp get nodes shows 1 node Ready.

Config (env overrides):
  GCP_PROJECT       GCP project ID (from sandbox credentials)
  GCP_ZONE          Compute zone (default: us-central1-a)
  GCP_MACHINE_TYPE  Instance machine type (default: e2-medium)
  GCP_INSTANCE_NAME VM instance name (default: k3s-gcp-server)
  GCP_SSH_KEY_FILE  SSH key for k3sup (default: ~/.ssh/k3d-manager-gcp-key)
HELP
    return 0
  fi

  if [[ ! -f "${_GCP_SSH_KEY_FILE}" || ! -f "${_GCP_SSH_KEY_FILE}.pub" ]]; then
    _err "[k3s-gcp] SSH key not found: ${_GCP_SSH_KEY_FILE}"
    _err "[k3s-gcp] Generate with: ssh-keygen -t ed25519 -f ${_GCP_SSH_KEY_FILE} -N \"\""
    return 1
  fi

  _info "[k3s-gcp] Extracting GCP sandbox credentials..."
  gcp_get_credentials "${_GCP_SANDBOX_URL:-}" || return 1

  local project="${GCP_PROJECT:-}"
  local key_file="${GOOGLE_APPLICATION_CREDENTIALS:-}"
  if [[ -z "${project}" ]]; then
    _err "[k3s-gcp] GCP_PROJECT is not set — credential extraction may have failed"
    return 1
  fi
  if [[ -z "${key_file}" || ! -f "${key_file}" ]]; then
    _err "[k3s-gcp] GOOGLE_APPLICATION_CREDENTIALS not set or key file not found: ${key_file}"
    return 1
  fi

  if ! command -v gcloud >/dev/null 2>&1; then
    _err "[k3s-gcp] gcloud CLI not found in PATH"
    return 1
  fi

  _info "[k3s-gcp] Activating service account for project ${project}..."
  gcloud auth activate-service-account --key-file="${key_file}" || return 1
  gcloud config set project "${project}" || return 1

  _info "[k3s-gcp] Checking for existing instance ${_GCP_INSTANCE_NAME}..."
  local existing
  existing=$(gcloud compute instances describe "${_GCP_INSTANCE_NAME}" \
    --zone="${_GCP_ZONE}" --format="value(name)" 2>/dev/null || true)
  if [[ -n "${existing}" ]]; then
    _info "[k3s-gcp] Instance already exists — skipping create"
  else
    _info "[k3s-gcp] Creating compute instance ${_GCP_INSTANCE_NAME}..."
    gcloud compute instances create "${_GCP_INSTANCE_NAME}" \
      --zone="${_GCP_ZONE}" \
      --machine-type="${_GCP_MACHINE_TYPE}" \
      --image-family=ubuntu-2204-lts \
      --image-project=ubuntu-os-cloud \
      --tags=k3s-server \
      --metadata="ssh-keys=ubuntu:$(<"${_GCP_SSH_KEY_FILE}.pub")" \
      --quiet || return 1
  fi

  _info "[k3s-gcp] Ensuring firewall rule for k3s API (tcp:6443)..."
  gcloud compute firewall-rules describe k3s-api --quiet 2>/dev/null \
    || gcloud compute firewall-rules create k3s-api \
         --allow=tcp:6443 \
         --target-tags=k3s-server \
         --description="k3s API server" \
         --quiet || return 1

  _info "[k3s-gcp] Fetching instance external IP..."
  local external_ip
  external_ip=$(gcloud compute instances describe "${_GCP_INSTANCE_NAME}" \
    --zone="${_GCP_ZONE}" --format="value(networkInterfaces[0].accessConfigs[0].natIP)") || return 1
  if [[ -z "${external_ip}" || "${external_ip}" == "None" || "${external_ip}" == "null" ]]; then
    _err "[k3s-gcp] Could not determine external IP for ${_GCP_INSTANCE_NAME}"
    return 1
  fi

  _ensure_k3sup || return 1
  _info "[k3s-gcp] Installing k3s via k3sup..."
  k3sup install \
    --ip "${external_ip}" \
    --user ubuntu \
    --ssh-key "${_GCP_SSH_KEY_FILE}" \
    --context k3s-gcp \
    --local-path "${_GCP_KUBECONFIG}" \
    --k3s-extra-args="--disable=traefik" || return 1

  mkdir -p "${HOME}/.kube"
  KUBECONFIG="${HOME}/.kube/config:${_GCP_KUBECONFIG}" \
    kubectl config view --flatten > "${HOME}/.kube/config.tmp" && \
    mv "${HOME}/.kube/config.tmp" "${HOME}/.kube/config"
  chmod 600 "${HOME}/.kube/config" "${_GCP_KUBECONFIG}"

  _info "[k3s-gcp] Labeling node..."
  kubectl --context k3s-gcp label nodes --all k3d-manager/node-type=server --overwrite || return 1

  _info "[k3s-gcp] Cluster provisioning complete."
}

function _provider_k3s_gcp_destroy_cluster() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: CLUSTER_PROVIDER=k3s-gcp ./scripts/k3d-manager destroy_cluster --confirm

Destroy the k3s-gcp cluster by deleting the GCE instance.

Requires --confirm to proceed.
HELP
    return 0
  fi

  if [[ "${1:-}" != "--confirm" ]]; then
    _err "[k3s-gcp] Refusing to destroy cluster without --confirm"
    return 1
  fi

  if ! command -v gcloud >/dev/null 2>&1; then
    _err "[k3s-gcp] gcloud CLI not found in PATH"
    return 1
  fi

  _info "[k3s-gcp] Deleting compute instance ${_GCP_INSTANCE_NAME}..."
  gcloud compute instances delete "${_GCP_INSTANCE_NAME}" \
    --zone="${_GCP_ZONE}" --quiet || return 1

  _info "[k3s-gcp] Removing kubeconfig context k3s-gcp..."
  kubectl config delete-context k3s-gcp 2>/dev/null || true
  kubectl config delete-cluster k3s-gcp 2>/dev/null || true
  rm -f "${_GCP_KUBECONFIG}"

  _info "[k3s-gcp] Cluster destroyed."
}
