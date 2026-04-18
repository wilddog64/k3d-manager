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
_GCP_SSH_HOST="ubuntu-gcp"

function _gcp_ssh_config_upsert() {
  local ip="$1"
  local config="${HOME}/.ssh/config"
  local tmp
  tmp=$(mktemp)
  # Strip existing ubuntu-gcp block (from Host line to next Host line, exclusive)
  awk '/^Host ubuntu-gcp$/{skip=1} skip && /^Host / && !/^Host ubuntu-gcp$/{skip=0} !skip{print}' \
    "${config}" > "${tmp}"
  # Append fresh entry
  printf '\nHost %s\n  HostName %s\n  User ubuntu\n  IdentityFile %s\n  IdentitiesOnly yes\n  StrictHostKeyChecking no\n' \
    "${_GCP_SSH_HOST}" "${ip}" "${_GCP_SSH_KEY_FILE}" >> "${tmp}"
  mv "${tmp}" "${config}"
  chmod 600 "${config}"
  _info "[k3s-gcp] ~/.ssh/config: Host ${_GCP_SSH_HOST} → ${ip}"
}

function _gcp_ssh_config_remove() {
  local config="${HOME}/.ssh/config"
  [[ ! -f "${config}" ]] && return 0
  local tmp
  tmp=$(mktemp)
  awk '/^Host ubuntu-gcp$/{skip=1} skip && /^Host / && !/^Host ubuntu-gcp$/{skip=0} !skip{print}' \
    "${config}" > "${tmp}"
  mv "${tmp}" "${config}"
  chmod 600 "${config}"
  _info "[k3s-gcp] ~/.ssh/config: Host ${_GCP_SSH_HOST} removed"
}

function _gcp_load_credentials() {
  local sandbox_url="${1:-}"
  local _default_key="${HOME}/.local/share/k3d-manager/gcp-service-account.json"
  local _cached_project
  _cached_project=$(jq -r '.project_id' "${_default_key}" 2>/dev/null || true)
  if [[ -f "${_default_key}" && -n "${_cached_project}" && "${_cached_project}" != "null" ]]; then
    if gcloud projects describe "${_cached_project}" --quiet >/dev/null 2>&1; then
      _info "[k3s-gcp] SA key valid on disk — skipping Playwright extraction"
      export GCP_PROJECT="${_cached_project}"
      export GOOGLE_APPLICATION_CREDENTIALS="${_default_key}"
      local _active_account
      _active_account=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null || true)
      [[ -n "${_active_account}" ]] && export GCP_USERNAME="${_active_account}"
    else
      _info "[k3s-gcp] Cached project ${_cached_project} not accessible — sandbox may have changed; re-extracting credentials..."
      rm -f "${_default_key}"
      gcloud auth revoke --all --quiet 2>/dev/null || true
      gcp_get_credentials "${sandbox_url}" || return 1
    fi
  else
    _info "[k3s-gcp] Extracting GCP sandbox credentials..."
    gcp_get_credentials "${sandbox_url}" || return 1
  fi
  if [[ -z "${GCP_PROJECT:-}" ]]; then
    _err "[k3s-gcp] GCP_PROJECT is not set after credential load"
    return 1
  fi
  if [[ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" || ! -f "${GOOGLE_APPLICATION_CREDENTIALS}" ]]; then
    _err "[k3s-gcp] GOOGLE_APPLICATION_CREDENTIALS not set or key file not found"
    return 1
  fi
}

function _provider_k3s_gcp_status() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: CLUSTER_PROVIDER=k3s-gcp ./scripts/k3d-manager status

Show instance state and Kubernetes status for the k3s-gcp cluster:
  1. gcloud compute instance describe (if credentials available)
  2. kubectl --context k3s-gcp get nodes
  3. kubectl --context k3s-gcp get pods --all-namespaces -o wide

Requires kubeconfig (~/.kube/k3s-gcp.yaml). Run `make up CLUSTER_PROVIDER=k3s-gcp`
first if the file is missing.
HELP
    return 0
  fi

  local kubeconfig="${_GCP_KUBECONFIG}"
  if [[ ! -f "${kubeconfig}" ]]; then
    _err "[k3s-gcp] ${kubeconfig} not found — run: make up CLUSTER_PROVIDER=k3s-gcp"
    return 1
  fi

  local project="${GCP_PROJECT:-}"
  if [[ -z "${project}" ]]; then
    local _default_key="${HOME}/.local/share/k3d-manager/gcp-service-account.json"
    if [[ -f "${_default_key}" ]]; then
      project=$(jq -r '.project_id' "${_default_key}" 2>/dev/null || true)
      [[ "${project}" == "null" ]] && project=""
    fi
  fi

  if [[ -n "${project}" ]] && _command_exist gcloud; then
    local _gcloud_token
    _gcloud_token=$(gcloud auth print-access-token 2>/dev/null || true)
    if [[ -z "${_gcloud_token}" ]]; then
      _info "[k3s-gcp] Stale gcloud credentials (sandbox rotated) — run: make up CLUSTER_PROVIDER=k3s-gcp to re-authenticate"
    else
      _info "[k3s-gcp] Instance ${_GCP_INSTANCE_NAME} (project ${project}, zone ${_GCP_ZONE})"
      _run_command --soft -- gcloud compute instances describe "${_GCP_INSTANCE_NAME}" \
        --project="${project}" \
        --zone="${_GCP_ZONE}" \
        --format='table(name,status,networkInterfaces[0].accessConfigs[0].natIP)' || true
    fi
  else
    _info "[k3s-gcp] Skipping gcloud instance describe (set GCP_PROJECT and ensure gcloud is installed)"
  fi

  _info "[k3s-gcp] kubectl get nodes (context k3s-gcp)"
  KUBECONFIG="${kubeconfig}" kubectl get nodes || return 1

  _info "[k3s-gcp] kubectl get pods --all-namespaces -o wide"
  KUBECONFIG="${kubeconfig}" kubectl get pods --all-namespaces -o wide || return 1
}

# Pre-flight guard: ensures console user has Compute IAM permissions
function _gcp_preflight_check_compute() {
  local project="$1"
  if ! gcloud compute instances list \
      --project="${project}" \
      --limit=1 \
      --quiet >/dev/null 2>&1; then
    _err "[k3s-gcp] Compute access check failed on project ${project}."
    _err "[k3s-gcp] Ensure gcloud is authenticated as a user with Compute permissions."
    _err "[k3s-gcp] Run: gcloud auth login  then retry: make up CLUSTER_PROVIDER=k3s-gcp"
    return 1
  fi
}

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
    _info "[k3s-gcp] SSH key not found — generating ${_GCP_SSH_KEY_FILE}..."
    mkdir -p "$(dirname "${_GCP_SSH_KEY_FILE}")"
    ssh-keygen -t ed25519 -f "${_GCP_SSH_KEY_FILE}" -N "" || return 1
  fi

  _gcp_load_credentials "${_GCP_SANDBOX_URL:-}" || return 1
  local project="${GCP_PROJECT}"

  _ensure_gcloud || return 1

  local username="${GCP_USERNAME:-}"
  if [[ -z "${username}" ]]; then
    _err "[k3s-gcp] GCP_USERNAME not set — credential extraction may have failed"
    return 1
  fi
  _info "[k3s-gcp] Ensuring gcloud is authenticated as ${username}..."
  gcp_login "${username}" || return 1
  export CLOUDSDK_CORE_PROJECT="${project}"

  _info "[k3s-gcp] Pre-flight: checking Compute IAM permissions..."
  _gcp_preflight_check_compute "${project}" || return 1

  _info "[k3s-gcp] Checking for existing instance ${_GCP_INSTANCE_NAME}..."
  local existing
  existing=$(gcloud compute instances describe "${_GCP_INSTANCE_NAME}" \
    --project="${project}" \
    --zone="${_GCP_ZONE}" --format="value(name)" 2>/dev/null || true)
  if [[ -n "${existing}" ]]; then
    _info "[k3s-gcp] Instance already exists — skipping create"
  else
    _info "[k3s-gcp] Creating compute instance ${_GCP_INSTANCE_NAME}..."
    gcloud compute instances create "${_GCP_INSTANCE_NAME}" \
      --project="${project}" \
      --zone="${_GCP_ZONE}" \
      --machine-type="${_GCP_MACHINE_TYPE}" \
      --image-family=ubuntu-2204-lts \
      --image-project=ubuntu-os-cloud \
      --tags=k3s-server \
      --metadata="ssh-keys=ubuntu:$(<"${_GCP_SSH_KEY_FILE}.pub")" \
      --quiet || return 1
  fi

  _info "[k3s-gcp] Ensuring firewall rule for k3s API (tcp:6443)..."
  gcloud compute firewall-rules describe k3s-api \
    --project="${project}" --quiet 2>/dev/null \
    || gcloud compute firewall-rules create k3s-api \
         --project="${project}" \
         --allow=tcp:6443 \
         --target-tags=k3s-server \
         --description="k3s API server" \
         --quiet || return 1

  _info "[k3s-gcp] Fetching instance external IP..."
  local external_ip
  external_ip=$(gcloud compute instances describe "${_GCP_INSTANCE_NAME}" \
    --project="${project}" \
    --zone="${_GCP_ZONE}" --format="value(networkInterfaces[0].accessConfigs[0].natIP)") || return 1
  if [[ -z "${external_ip}" || "${external_ip}" == "None" || "${external_ip}" == "null" ]]; then
    _err "[k3s-gcp] Could not determine external IP for ${_GCP_INSTANCE_NAME}"
    return 1
  fi

  _gcp_ssh_config_upsert "${external_ip}"

  _info "[k3s-gcp] Waiting for SSH on ${external_ip}..."
  local _ssh_retries=30
  local _ssh_i=0
  while (( _ssh_i < _ssh_retries )); do
    if nc -z -w 5 "${external_ip}" 22 2>/dev/null; then
      _info "[k3s-gcp] SSH port open on ${external_ip}"
      break
    fi
    _ssh_i=$(( _ssh_i + 1 ))
    _info "[k3s-gcp] SSH not ready yet (${_ssh_i}/${_ssh_retries}) — retrying in 10s..."
    sleep 10
  done
  if (( _ssh_i >= _ssh_retries )); then
    _err "[k3s-gcp] SSH not available on ${external_ip} after $(( _ssh_retries * 10 ))s"
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
  kubectl config delete-context k3s-gcp 2>/dev/null || true
  kubectl config delete-cluster k3s-gcp 2>/dev/null || true
  kubectl config delete-user k3s-gcp 2>/dev/null || true
  KUBECONFIG="${HOME}/.kube/config:${_GCP_KUBECONFIG}" \
    kubectl config view --flatten > "${HOME}/.kube/config.tmp" && \
    mv "${HOME}/.kube/config.tmp" "${HOME}/.kube/config"
  chmod 600 "${HOME}/.kube/config" "${_GCP_KUBECONFIG}"

  _info "[k3s-gcp] Waiting for k3s API server on ${external_ip}:6443..."
  local _api_retries=30
  local _api_i=0
  while (( _api_i < _api_retries )); do
    if nc -z -w 5 "${external_ip}" 6443 2>/dev/null; then
      _info "[k3s-gcp] k3s API server ready on ${external_ip}:6443"
      break
    fi
    _api_i=$(( _api_i + 1 ))
    _info "[k3s-gcp] API server not ready yet (${_api_i}/${_api_retries}) — retrying in 10s..."
    sleep 10
  done
  if (( _api_i >= _api_retries )); then
    _err "[k3s-gcp] k3s API server not available on ${external_ip}:6443 after $(( _api_retries * 10 ))s"
    return 1
  fi

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

  _gcp_ssh_config_remove

  _info "[k3s-gcp] Cluster destroyed."
}
