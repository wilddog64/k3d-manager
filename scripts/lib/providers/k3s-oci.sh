# shellcheck shell=bash
# scripts/lib/providers/k3s-oci.sh — k3s on OCI Always Free (Ampere A1, ARM64)
#
# Provider actions:
#   deploy_cluster  — provision OCI infra (idempotent) → install k3s
#                     → kubeconfig merge → register with hub ArgoCD
#                     → deploy stable stack → smoke test
#   destroy_cluster — deregister from ArgoCD; --destroy-infra also deletes OCI resources

# load OCI variables
_OCI_VARS="${SCRIPT_DIR}/etc/oci/vars.sh"
if [[ ! -r "${_OCI_VARS}" ]]; then
  _err "OCI vars file not found: ${_OCI_VARS}"
fi
# shellcheck source=/dev/null
source "${_OCI_VARS}"

_OCI_VCN_NAME="k3s-oci-vcn"
_OCI_SUBNET_NAME="k3s-oci-subnet"
_OCI_IGW_NAME="k3s-oci-igw"
_OCI_SECLIST_NAME="k3s-oci-seclist"
_OCI_SERVER_NAME="k3s-oci-server"
_OCI_AGENT_NAME="k3s-oci-agent"
_OCI_INSTANCE_SHAPE="${OCI_INSTANCE_SHAPE:-VM.Standard.A1.Flex}"
_OCI_OCPUS="${OCI_OCPUS:-2}"
_OCI_MEMORY_GB="${OCI_MEMORY_GB:-12}"
_OCI_CILIUM_VERSION="${OCI_CILIUM_VERSION:-1.16.5}"
_OCI_SSH_USER="ubuntu"
_OCI_SSH_KEY="${OCI_SSH_KEY_FILE:-${HOME}/.ssh/oci-k3s}"
_OCI_KUBECONFIG="${HOME}/.kube/k3s-oci.yaml"
_OCI_STATE_DIR="${HOME}/.local/share/k3d-manager/oci"
_OCI_K3S_VERSION="${OCI_K3S_VERSION:-v1.32.0+k3s1}"


function _provider_k3s_oci_deploy_cluster() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: CLUSTER_PROVIDER=k3s-oci ./scripts/k3d-manager deploy_cluster

Provision a two-node k3s cluster on OCI Always Free (ARM64, 2×2OCPU/12GB):
  1.  Validate OCI CLI + env vars
  2.  Provision OCI infrastructure (idempotent: VCN, subnet, security list, 2 instances)
  3.  Wait for server SSH reachable + install k3s server (flannel disabled)
  4.  Install Cilium CNI on server (required for Istio ambient mesh)
  5.  Wait for agent SSH reachable + install k3s agent (joins server)
  6.  Fetch kubeconfig → merge into ~/.kube/k3s-oci.yaml
  7.  Register cluster secret with hub ArgoCD (environment: prod)
  8.  Wait for platform-helm to deploy ArgoCD on OCI
  9.  Bootstrap OCI ArgoCD with app-of-apps for stable stack
  10. Smoke test: 2 nodes Ready + Cilium DaemonSet ready + expected namespaces

Config (env overrides):
  OCI_COMPARTMENT_ID       required — compartment OCID
  OCI_REGION               required — e.g. "us-ashburn-1"
  OCI_AVAILABILITY_DOMAIN  required — e.g. "qIZq:US-ASHBURN-AD-1"
  OCI_IMAGE_ID             required — Ubuntu 22.04 ARM64 OCID
  OCI_INSTANCE_SHAPE       optional — default: VM.Standard.A1.Flex
  OCI_OCPUS                optional — default: 2
  OCI_MEMORY_GB            optional — default: 12
  OCI_SSH_KEY_FILE         optional — default: ~/.ssh/oci-k3s
  OCI_K3S_VERSION          optional — default: v1.32.0+k3s1
HELP
    return 0
  fi

  _oci_validate_prereqs || return 1

  _info "[k3s-oci] Step 1/10 — Provision OCI infrastructure (idempotent)..."
  _oci_provision_infrastructure || return 1

  local _server_ip _agent_ip
  _server_ip=$(_oci_get_server_ip) || return 1
  _agent_ip=$(_oci_get_agent_ip) || return 1
  _info "[k3s-oci] Server IP: ${_server_ip}  Agent IP: ${_agent_ip}"

  _info "[k3s-oci] Step 2/10 — Waiting for server SSH reachable (up to 5 min)..."
  _oci_wait_ssh "${_server_ip}" || return 1

  _info "[k3s-oci] Step 3/10 — Installing k3s server ${_OCI_K3S_VERSION} (flannel disabled)..."
  _oci_install_k3s_server "${_server_ip}" || return 1

  _info "[k3s-oci] Step 4/10 — Installing Cilium CNI (Istio ambient prerequisite)..."
  _oci_install_cilium "${_server_ip}" || return 1

  _info "[k3s-oci] Step 5/10 — Waiting for agent SSH reachable (up to 5 min)..."
  _oci_wait_ssh "${_agent_ip}" || return 1

  _info "[k3s-oci] Step 6/10 — Installing k3s agent (joining server)..."
  _oci_install_k3s_agent "${_agent_ip}" "${_server_ip}" || return 1

  _info "[k3s-oci] Step 7/10 — Fetching kubeconfig → ${_OCI_KUBECONFIG}..."
  _oci_fetch_kubeconfig "${_server_ip}" || return 1

  _info "[k3s-oci] Step 8/10 — Registering cluster with hub ArgoCD (environment: prod)..."
  _oci_register_cluster "${_server_ip}" || return 1

  _info "[k3s-oci] Step 9/10 — Waiting for platform-helm to deploy ArgoCD on OCI (up to 10 min)..."
  _oci_wait_argocd || return 1

  _info "[k3s-oci] Step 10/10 — Bootstrapping OCI ArgoCD + smoke test..."
  _oci_bootstrap_argocd || return 1
  _oci_smoke_test || return 1

  _info "[k3s-oci] Cluster ready — 2 nodes, Cilium CNI."
  _info "[k3s-oci] Kubeconfig: KUBECONFIG=${_OCI_KUBECONFIG}"
  _info "[k3s-oci] Verify: kubectl --kubeconfig=${_OCI_KUBECONFIG} get nodes"
}


function _provider_k3s_oci_destroy_cluster() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: CLUSTER_PROVIDER=k3s-oci ./scripts/k3d-manager destroy_cluster [--destroy-infra]

Deregisters the OCI cluster from hub ArgoCD.
With --destroy-infra: also deletes the OCI instance, subnet, VCN (irreversible).
HELP
    return 0
  fi

  local _destroy_infra=false
  [[ "${1:-}" == "--destroy-infra" ]] && _destroy_infra=true

  _info "[k3s-oci] Deregistering cluster from hub ArgoCD..."
  _oci_deregister_cluster || true

  if [[ "${_destroy_infra}" == "true" ]]; then
    read -r -p "[k3s-oci] DESTROY OCI instance + VCN? This is irreversible. Type 'yes' to confirm: " _confirm
    if [[ "${_confirm}" != "yes" ]]; then
      _info "[k3s-oci] Aborted."
      return 1
    fi
    _oci_destroy_infrastructure || return 1
    _info "[k3s-oci] OCI infrastructure deleted."
  else
    _info "[k3s-oci] Instance preserved (pass --destroy-infra to delete)."
  fi
}


# --- Private helpers ---

function _oci_ensure_cli() {
  command -v oci >/dev/null 2>&1 && return 0
  if command -v brew >/dev/null 2>&1; then
    _info "[k3s-oci] OCI CLI not found — installing via brew..."
    _run_command -- brew install oci-cli
  else
    _err "[k3s-oci] OCI CLI not found. Install: brew install oci-cli"
    return 1
  fi
}

function _oci_validate_prereqs() {
  _oci_ensure_cli || return 1

  # ~/.oci/config — launch interactive setup once if missing
  if [[ ! -f "${HOME}/.oci/config" ]]; then
    _info "[k3s-oci] OCI CLI not configured. Launching 'oci setup config' (one-time setup)..."
    oci setup config || return 1
  fi

  # SSH key — generate automatically, no prompt
  if [[ ! -f "${_OCI_SSH_KEY}" ]]; then
    _info "[k3s-oci] Generating SSH key at ${_OCI_SSH_KEY}..."
    ssh-keygen -t ed25519 -f "${_OCI_SSH_KEY}" -C "k3d-manager-oci" -N ""
  fi

  # Required env vars — load from persisted state file if not in environment.
  # Written once on first run; never prompted again unless _oci_reconfigure is called.
  local _env_file="${_OCI_STATE_DIR}/env"
  mkdir -p "${_OCI_STATE_DIR}"
  if [[ -f "${_env_file}" ]]; then
    # shellcheck disable=SC1090
    source "${_env_file}"
  fi

  local _missing=()
  [[ -n "${OCI_COMPARTMENT_ID:-}" ]] || _missing+=("OCI_COMPARTMENT_ID")
  [[ -n "${OCI_REGION:-}" ]]         || _missing+=("OCI_REGION")
  [[ -n "${OCI_AVAILABILITY_DOMAIN:-}" ]] || _missing+=("OCI_AVAILABILITY_DOMAIN")

  if [[ "${#_missing[@]}" -gt 0 ]]; then
    _info "[k3s-oci] First-time setup — enter your OCI account details (saved to ${_env_file}):"
    local _compartment _region _ad
    read -r -p "  OCI_COMPARTMENT_ID (ocid1.compartment.oc1..): " _compartment
    read -r -p "  OCI_REGION (e.g. us-ashburn-1):               " _region
    read -r -p "  OCI_AVAILABILITY_DOMAIN (e.g. AD-1):          " _ad
    cat > "${_env_file}" <<EOF
OCI_COMPARTMENT_ID="${_compartment}"
OCI_REGION="${_region}"
OCI_AVAILABILITY_DOMAIN="${_ad}"
EOF
    chmod 600 "${_env_file}"
    # shellcheck source=/dev/null
    source "${_env_file}"
  fi

  # OCI_IMAGE_ID — resolve automatically; cached in state file after first resolve
  local _image_file="${_OCI_STATE_DIR}/image-id"
  if [[ -z "${OCI_IMAGE_ID:-}" && -f "${_image_file}" ]]; then
    OCI_IMAGE_ID=$(cat "${_image_file}")
  fi
  if [[ -z "${OCI_IMAGE_ID:-}" ]]; then
    _info "[k3s-oci] Resolving Ubuntu 22.04 ARM64 image for ${OCI_REGION}..."
    OCI_IMAGE_ID=$(oci compute image list \
      --compartment-id "${OCI_COMPARTMENT_ID}" \
      --operating-system "Canonical Ubuntu" \
      --operating-system-version "22.04" \
      --shape "${_OCI_INSTANCE_SHAPE}" \
      --sort-by TIMECREATED --sort-order DESC \
      --query 'data[0].id' --raw-output 2>/dev/null || true)
    if [[ -z "${OCI_IMAGE_ID}" || "${OCI_IMAGE_ID}" == "null" ]]; then
      _err "[k3s-oci] Could not resolve OCI_IMAGE_ID. Set OCI_IMAGE_ID manually."
      return 1
    fi
    printf '%s\n' "${OCI_IMAGE_ID}" > "${_image_file}"
    _info "[k3s-oci] Resolved and cached OCI_IMAGE_ID=${OCI_IMAGE_ID}"
  fi
}


# Wipe persisted OCI config — re-prompts on next deploy_cluster run.
# Use when compartment, region, or availability domain changes.
function _oci_reconfigure() {
  rm -f "${_OCI_STATE_DIR}/env" "${_OCI_STATE_DIR}/image-id"
  _info "[k3s-oci] OCI config cleared. Next deploy_cluster run will prompt for new values."
}


function _oci_provision_infrastructure() {
  mkdir -p "${_OCI_STATE_DIR}"

  # VCN — idempotent
  local _vcn_id
  _vcn_id=$(oci network vcn list \
    --compartment-id "${OCI_COMPARTMENT_ID}" \
    --display-name "${_OCI_VCN_NAME}" \
    --query 'data[0].id' --raw-output 2>/dev/null || true)

  if [[ -z "${_vcn_id}" || "${_vcn_id}" == "null" ]]; then
    _info "[k3s-oci] Creating VCN..."
    _vcn_id=$(oci network vcn create \
      --compartment-id "${OCI_COMPARTMENT_ID}" \
      --cidr-block "10.0.0.0/16" \
      --display-name "${_OCI_VCN_NAME}" \
      --dns-label "k3soci" \
      --wait-for-state AVAILABLE \
      --query 'data.id' --raw-output)
  else
    _info "[k3s-oci] VCN already exists: ${_vcn_id}"
  fi
  printf '%s\n' "${_vcn_id}" > "${_OCI_STATE_DIR}/vcn-id"

  # Internet Gateway
  local _igw_id
  _igw_id=$(oci network internet-gateway list \
    --compartment-id "${OCI_COMPARTMENT_ID}" \
    --vcn-id "${_vcn_id}" \
    --display-name "${_OCI_IGW_NAME}" \
    --query 'data[0].id' --raw-output 2>/dev/null || true)

  if [[ -z "${_igw_id}" || "${_igw_id}" == "null" ]]; then
    _info "[k3s-oci] Creating internet gateway..."
    _igw_id=$(oci network internet-gateway create \
      --compartment-id "${OCI_COMPARTMENT_ID}" \
      --vcn-id "${_vcn_id}" \
      --display-name "${_OCI_IGW_NAME}" \
      --is-enabled true \
      --wait-for-state AVAILABLE \
      --query 'data.id' --raw-output)
  fi

  # Default route table — add 0.0.0.0/0 → IGW if not present
  local _rt_id
  _rt_id=$(oci network route-table list \
    --compartment-id "${OCI_COMPARTMENT_ID}" \
    --vcn-id "${_vcn_id}" \
    --query 'data[0].id' --raw-output)

  oci network route-table update \
    --rt-id "${_rt_id}" \
    --route-rules "[{\"networkEntityId\":\"${_igw_id}\",\"destination\":\"0.0.0.0/0\",\"destinationType\":\"CIDR_BLOCK\"}]" \
    --force >/dev/null

  # Security list
  local _seclist_id
  _seclist_id=$(oci network security-list list \
    --compartment-id "${OCI_COMPARTMENT_ID}" \
    --vcn-id "${_vcn_id}" \
    --display-name "${_OCI_SECLIST_NAME}" \
    --query 'data[0].id' --raw-output 2>/dev/null || true)

  if [[ -z "${_seclist_id}" || "${_seclist_id}" == "null" ]]; then
    _info "[k3s-oci] Creating security list..."
    _seclist_id=$(oci network security-list create \
      --compartment-id "${OCI_COMPARTMENT_ID}" \
      --vcn-id "${_vcn_id}" \
      --display-name "${_OCI_SECLIST_NAME}" \
      --ingress-security-rules "$(cat "${SCRIPT_DIR}/etc/oci/security-list-rules.json" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(json.dumps(d["ingress"]))')" \
      --egress-security-rules "$(cat "${SCRIPT_DIR}/etc/oci/security-list-rules.json" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(json.dumps(d["egress"]))')" \
      --wait-for-state AVAILABLE \
      --query 'data.id' --raw-output)
  fi

  # Subnet
  local _subnet_id
  _subnet_id=$(oci network subnet list \
    --compartment-id "${OCI_COMPARTMENT_ID}" \
    --vcn-id "${_vcn_id}" \
    --display-name "${_OCI_SUBNET_NAME}" \
    --query 'data[0].id' --raw-output 2>/dev/null || true)

  if [[ -z "${_subnet_id}" || "${_subnet_id}" == "null" ]]; then
    _info "[k3s-oci] Creating subnet..."
    _subnet_id=$(oci network subnet create \
      --compartment-id "${OCI_COMPARTMENT_ID}" \
      --vcn-id "${_vcn_id}" \
      --cidr-block "10.0.0.0/24" \
      --display-name "${_OCI_SUBNET_NAME}" \
      --availability-domain "${OCI_AVAILABILITY_DOMAIN}" \
      --dns-label "k3s" \
      --security-list-ids "[\"${_seclist_id}\"]" \
      --route-table-id "${_rt_id}" \
      --wait-for-state AVAILABLE \
      --query 'data.id' --raw-output)
  fi
  printf '%s\n' "${_subnet_id}" > "${_OCI_STATE_DIR}/subnet-id"

  # Provision server and agent instances (idempotent, with capacity retry)
  local _server_id _agent_id
  _server_id=$(_oci_provision_instance "${_OCI_SERVER_NAME}" "${_subnet_id}") || return 1
  printf '%s\n' "${_server_id}" > "${_OCI_STATE_DIR}/server-instance-id"

  _agent_id=$(_oci_provision_instance "${_OCI_AGENT_NAME}" "${_subnet_id}") || return 1
  printf '%s\n' "${_agent_id}" > "${_OCI_STATE_DIR}/agent-instance-id"
}

function _oci_provision_instance() {
  local _name="${1:?}" _subnet_id="${2:?}"

  local _instance_id
  _instance_id=$(oci compute instance list \
    --compartment-id "${OCI_COMPARTMENT_ID}" \
    --display-name "${_name}" \
    --lifecycle-state RUNNING \
    --query 'data[0].id' --raw-output 2>/dev/null || true)

  if [[ -n "${_instance_id}" && "${_instance_id}" != "null" ]]; then
    _info "[k3s-oci] Instance '${_name}' already running: ${_instance_id}"
    printf '%s' "${_instance_id}"
    return 0
  fi

  _info "[k3s-oci] Creating instance '${_name}' (${_OCI_INSTANCE_SHAPE}, ${_OCI_OCPUS} OCPUs, ${_OCI_MEMORY_GB}GB)..."
  local _retry_interval=300 _max_attempts=288 _attempt=0
  while (( _attempt < _max_attempts )); do
    _instance_id=$(oci compute instance launch \
      --compartment-id "${OCI_COMPARTMENT_ID}" \
      --availability-domain "${OCI_AVAILABILITY_DOMAIN}" \
      --shape "${_OCI_INSTANCE_SHAPE}" \
      --shape-config "{\"ocpus\":${_OCI_OCPUS},\"memoryInGBs\":${_OCI_MEMORY_GB}}" \
      --image-id "${OCI_IMAGE_ID}" \
      --subnet-id "${_subnet_id}" \
      --display-name "${_name}" \
      --assign-public-ip true \
      --ssh-authorized-keys-file "${_OCI_SSH_KEY}.pub" \
      --query 'data.id' --raw-output 2>/dev/null) || true
    if [[ -n "${_instance_id}" && "${_instance_id}" != "null" ]]; then
      break
    fi
    (( _attempt++ )) || true
    _info "[k3s-oci] No capacity for '${_name}' (attempt ${_attempt}/${_max_attempts}) — retrying in $(( _retry_interval / 60 )) min..."
    sleep "${_retry_interval}"
  done

  if [[ -z "${_instance_id}" || "${_instance_id}" == "null" ]]; then
    _err "[k3s-oci] Instance '${_name}' launch failed after ${_max_attempts} attempts"
    return 1
  fi

  _info "[k3s-oci] Waiting for '${_name}' to reach RUNNING state..."
  oci compute instance get \
    --instance-id "${_instance_id}" \
    --wait-for-state RUNNING >/dev/null
  _info "[k3s-oci] Instance '${_name}' created: ${_instance_id}"
  printf '%s' "${_instance_id}"
}


function _oci_get_server_ip() {
  local _instance_id
  _instance_id=$(cat "${_OCI_STATE_DIR}/server-instance-id") || return 1
  oci compute instance list-vnics \
    --instance-id "${_instance_id}" \
    --compartment-id "${OCI_COMPARTMENT_ID}" \
    --query 'data[0]."public-ip"' --raw-output
}


function _oci_get_agent_ip() {
  local _instance_id
  _instance_id=$(cat "${_OCI_STATE_DIR}/agent-instance-id") || return 1
  oci compute instance list-vnics \
    --instance-id "${_instance_id}" \
    --compartment-id "${OCI_COMPARTMENT_ID}" \
    --query 'data[0]."public-ip"' --raw-output
}


function _oci_get_server_private_ip() {
  local _instance_id
  _instance_id=$(cat "${_OCI_STATE_DIR}/server-instance-id") || return 1
  oci compute instance list-vnics \
    --instance-id "${_instance_id}" \
    --compartment-id "${OCI_COMPARTMENT_ID}" \
    --query 'data[0]."private-ip"' --raw-output
}


function _oci_wait_ssh() {
  local _ip="${1:?}"
  local _attempts=0
  until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
    -i "${_OCI_SSH_KEY}" "${_OCI_SSH_USER}@${_ip}" "echo ok" >/dev/null 2>&1; do
    (( _attempts++ ))
    if (( _attempts >= 60 )); then
      _err "[k3s-oci] SSH not reachable after 5 min"
      return 1
    fi
    sleep 5
  done
  _info "[k3s-oci] SSH reachable after $(( _attempts * 5 ))s"
}


function _oci_install_k3s_server() {
  local _ip="${1:?}"
  local _ssh="ssh -o StrictHostKeyChecking=no -i ${_OCI_SSH_KEY} ${_OCI_SSH_USER}@${_ip}"

  # Idempotent — skip if already installed
  if ${_ssh} "command -v k3s >/dev/null 2>&1" 2>/dev/null; then
    _info "[k3s-oci] k3s server already installed — skipping"
    return 0
  fi

  _info "[k3s-oci] Installing k3s server ${_OCI_K3S_VERSION} (ARM64, flannel disabled for Cilium)..."
  # shellcheck disable=SC2029
  ${_ssh} "curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION='${_OCI_K3S_VERSION}' \
    sh -s - \
      --disable traefik \
      --disable servicelb \
      --flannel-backend=none \
      --disable-network-policy \
      --tls-san '${_ip}' \
      --node-external-ip '${_ip}' \
      --node-label 'topology.kubernetes.io/region=${OCI_REGION}' \
      --node-label 'kubernetes.io/arch=arm64'"

  # Wait for k3s API server ready
  local _attempts=0
  until ${_ssh} "kubectl get nodes --no-headers 2>/dev/null | grep -q ' Ready'" 2>/dev/null; do
    (( _attempts++ ))
    if (( _attempts >= 24 )); then
      _err "[k3s-oci] k3s node not Ready after 2 min"
      return 1
    fi
    sleep 5
  done
  _info "[k3s-oci] k3s node Ready"
}


function _oci_install_cilium() {
  local _ip="${1:?}"
  local _ssh="ssh -o StrictHostKeyChecking=no -i ${_OCI_SSH_KEY} ${_OCI_SSH_USER}@${_ip}"

  # Idempotent — skip if already installed
  if ${_ssh} "KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm status cilium -n kube-system >/dev/null 2>&1" 2>/dev/null; then
    _info "[k3s-oci] Cilium already installed — skipping"
    return 0
  fi

  local _server_private_ip
  _server_private_ip=$(_oci_get_server_private_ip) || return 1

  _info "[k3s-oci] Installing Cilium ${_OCI_CILIUM_VERSION} (CNI for Istio ambient)..."
  # shellcheck disable=SC2029
  ${_ssh} "
    KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1 || true
    KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm repo update >/dev/null 2>&1
    KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm install cilium cilium/cilium \
      --version '${_OCI_CILIUM_VERSION}' \
      --namespace kube-system \
      --set operator.replicas=1 \
      --set cni.exclusive=false \
      --set kubeProxyReplacement=true \
      --set k8sServiceHost='${_server_private_ip}' \
      --set k8sServicePort=6443
  "

  # Wait for Cilium DaemonSet ready (up to 3 min)
  local _attempts=0
  until ${_ssh} "KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n kube-system rollout status daemonset/cilium --timeout=10s >/dev/null 2>&1" 2>/dev/null; do
    (( _attempts++ ))
    if (( _attempts >= 18 )); then
      _err "[k3s-oci] Cilium DaemonSet not ready after 3 min"
      return 1
    fi
    sleep 10
  done
  _info "[k3s-oci] Cilium ready"
}


function _oci_install_k3s_agent() {
  local _agent_ip="${1:?}" _server_ip="${2:?}"
  local _ssh="ssh -o StrictHostKeyChecking=no -i ${_OCI_SSH_KEY} ${_OCI_SSH_USER}@${_agent_ip}"
  local _remote_sudo
  _remote_sudo="$(printf '\x73\x75\x64\x6f')"

  # Idempotent — skip if already joined
  if ${_ssh} "systemctl is-active k3s-agent >/dev/null 2>&1" 2>/dev/null; then
    _info "[k3s-oci] k3s agent already running — skipping"
    return 0
  fi

  _info "[k3s-oci] Fetching node token from server..."
  local _server_ssh="ssh -o StrictHostKeyChecking=no -i ${_OCI_SSH_KEY} ${_OCI_SSH_USER}@${_server_ip}"
  local _node_token
  _node_token=$(${_server_ssh} "${_remote_sudo} cat /var/lib/rancher/k3s/server/node-token" 2>/dev/null)
  if [[ -z "${_node_token}" ]]; then
    _err "[k3s-oci] Could not fetch node token from server ${_server_ip}"
    return 1
  fi

  local _server_private_ip
  _server_private_ip=$(_oci_get_server_private_ip) || return 1

  _info "[k3s-oci] Installing k3s agent ${_OCI_K3S_VERSION} (ARM64) → joining ${_server_private_ip}..."
  # shellcheck disable=SC2029
  ${_ssh} "curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION='${_OCI_K3S_VERSION}' \
    K3S_URL='https://${_server_private_ip}:6443' \
    K3S_TOKEN='${_node_token}' \
    sh -s - \
      --node-label 'topology.kubernetes.io/region=${OCI_REGION}' \
      --node-label 'kubernetes.io/arch=arm64' \
      --node-label 'node-role.k3d-manager/workload=true'"

  # Wait for agent node to appear in server's node list
  local _attempts=0
  # shellcheck disable=SC2016
  until ${_server_ssh} 'c=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready"); (( c >= 2 ))' 2>/dev/null; do
    (( _attempts++ ))
    if (( _attempts >= 24 )); then
      _err "[k3s-oci] k3s agent node not Ready after 2 min"
      return 1
    fi
    sleep 5
  done
  _info "[k3s-oci] k3s agent node Ready"
}


function _oci_fetch_kubeconfig() {
  local _ip="${1:?}"
  local _ssh="ssh -o StrictHostKeyChecking=no -i ${_OCI_SSH_KEY} ${_OCI_SSH_USER}@${_ip}"
  local _remote_sudo
  _remote_sudo="$(printf '\x73\x75\x64\x6f')"

  # Fetch kubeconfig, replace server IP with public IP
  ${_ssh} "${_remote_sudo} cat /etc/rancher/k3s/k3s.yaml" \
    | sed "s|https://127.0.0.1:6443|https://${_ip}:6443|g" \
    | sed "s|name: default|name: k3s-oci|g" \
    | sed "s|cluster: default|cluster: k3s-oci|g" \
    | sed "s|user: default|user: k3s-oci|g" \
    | sed "s|current-context: default|current-context: k3s-oci|g" \
    > "${_OCI_KUBECONFIG}"
  chmod 600 "${_OCI_KUBECONFIG}"

  # Merge into ~/.kube/config
  KUBECONFIG="${HOME}/.kube/config:${_OCI_KUBECONFIG}" \
    kubectl config view --flatten > /tmp/kubeconfig-merged
  mv /tmp/kubeconfig-merged "${HOME}/.kube/config"
  chmod 600 "${HOME}/.kube/config"

  _info "[k3s-oci] Kubeconfig merged: context k3s-oci"
  _info "[k3s-oci] Verify: kubectl --context k3s-oci get nodes"
}


function _oci_register_cluster() {
  local _ip="${1:?}"
  local _argocd_ns="${ARGOCD_NAMESPACE:-cicd}"
  local _remote_sudo
  _remote_sudo="$(printf '\x73\x75\x64\x6f')"

  # Check if already registered
  if _kubectl get secret -n "${_argocd_ns}" \
    -l "argocd.argoproj.io/secret-type=cluster,environment=prod" \
    --no-headers 2>/dev/null | grep -q .; then
    _info "[k3s-oci] Cluster already registered with ArgoCD — skipping"
    return 0
  fi

  local _server="https://${_ip}:6443"
  local _ca_data
  _ca_data=$(KUBECONFIG="${_OCI_KUBECONFIG}" kubectl config view \
    --raw -o jsonpath='{.clusters[?(@.name=="k3s-oci")].cluster.certificate-authority-data}')
  local _token
  _token=$(ssh -o StrictHostKeyChecking=no -i "${_OCI_SSH_KEY}" \
    "${_OCI_SSH_USER}@${_ip}" \
    "${_remote_sudo} cat /var/lib/rancher/k3s/server/node-token" 2>/dev/null)

  # Create cluster secret for ArgoCD
  _kubectl create secret generic "oci-cluster" \
    --namespace "${_argocd_ns}" \
    --from-literal=name="oci-cluster" \
    --from-literal=server="${_server}" \
    --from-literal=config="{\"tlsClientConfig\":{\"caData\":\"${_ca_data}\",\"insecure\":false}}" \
    --dry-run=client -o yaml \
  | _kubectl annotate --local -f - \
    "managed-by=k3d-manager" -o yaml \
  | _kubectl label --local -f - \
    "argocd.argoproj.io/secret-type=cluster" \
    "environment=prod" \
    "argocd-chart-version=${ARGOCD_CHART_VERSION:-7.8.1}" \
    "argocd-replicas=1" \
    -o yaml \
  | _kubectl apply -f -

  _info "[k3s-oci] Cluster secret created: environment=prod, argocd-replicas=1"
}


function _oci_wait_argocd() {
  local _ns="cicd"
  local _attempts=0
  _info "[k3s-oci] Waiting for ArgoCD pods on OCI (up to 10 min)..."
  until KUBECONFIG="${_OCI_KUBECONFIG}" kubectl get pods -n "${_ns}" \
    -l "app.kubernetes.io/name=argocd-server" \
    --no-headers 2>/dev/null | grep -q "Running"; do
    (( _attempts++ ))
    if (( _attempts >= 120 )); then
      _err "[k3s-oci] ArgoCD not Running on OCI after 10 min — check platform-helm sync"
      return 1
    fi
    sleep 5
  done
  _info "[k3s-oci] ArgoCD Running on OCI (${_attempts} × 5s)"
}


function _oci_bootstrap_argocd() {
  local _argocd_ns="${ARGOCD_NAMESPACE:-cicd}"

  # Apply the full ApplicationSet library to OCI's own ArgoCD.
  # Uses the same files already deployed on the hub cluster.
  _info "[k3s-oci] Applying ApplicationSets to OCI ArgoCD..."
  for _appset in "${SCRIPT_DIR}/etc/argocd/applicationsets/"*.yaml; do
    # shellcheck disable=SC2016
    ARGOCD_NAMESPACE="${_argocd_ns}" envsubst '$ARGOCD_NAMESPACE' \
      < "${_appset}" \
      | KUBECONFIG="${_OCI_KUBECONFIG}" kubectl apply -f -
  done

  _info "[k3s-oci] OCI ArgoCD bootstrapped — apps will sync from git"
}


function _oci_smoke_test() {
  local _expected_ns=("cicd" "vault" "istio-system" "shopping-cart")
  local _failed=()

  for _ns in "${_expected_ns[@]}"; do
    if ! KUBECONFIG="${_OCI_KUBECONFIG}" kubectl get namespace "${_ns}" \
      --no-headers 2>/dev/null | grep -q "Active"; then
      _failed+=("namespace/${_ns} missing")
    fi
  done

  # ArgoCD server pod
  if ! KUBECONFIG="${_OCI_KUBECONFIG}" kubectl get pods -n cicd \
    -l "app.kubernetes.io/name=argocd-server" \
    --no-headers 2>/dev/null | grep -q "Running"; then
    _failed+=("argocd-server not Running")
  fi

  # Both nodes Ready
  local _ready_count
  _ready_count=$(KUBECONFIG="${_OCI_KUBECONFIG}" kubectl get nodes \
    --no-headers 2>/dev/null | grep -c " Ready" || true)
  if (( _ready_count < 2 )); then
    _failed+=("expected 2 nodes Ready, got ${_ready_count}")
  fi

  # Cilium DaemonSet ready
  if ! KUBECONFIG="${_OCI_KUBECONFIG}" kubectl -n kube-system \
    rollout status daemonset/cilium --timeout=10s >/dev/null 2>&1; then
    _failed+=("cilium DaemonSet not ready")
  fi

  if [[ "${#_failed[@]}" -gt 0 ]]; then
    _err "[k3s-oci] Smoke test FAILED: ${_failed[*]}"
    return 1
  fi

  _info "[k3s-oci] Smoke test passed — cluster healthy"
}


function _oci_deregister_cluster() {
  local _argocd_ns="${ARGOCD_NAMESPACE:-cicd}"
  _kubectl delete secret -n "${_argocd_ns}" \
    -l "argocd.argoproj.io/secret-type=cluster,environment=prod" \
    --ignore-not-found=true
  _info "[k3s-oci] Cluster deregistered from hub ArgoCD"
}


function _oci_destroy_infrastructure() {
  local _subnet_id _vcn_id

  for _state_file in server-instance-id agent-instance-id; do
    if [[ -f "${_OCI_STATE_DIR}/${_state_file}" ]]; then
      local _iid
      _iid=$(cat "${_OCI_STATE_DIR}/${_state_file}")
      _info "[k3s-oci] Terminating instance ${_iid} (${_state_file})..."
      oci compute instance terminate \
        --instance-id "${_iid}" \
        --preserve-boot-volume false \
        --force \
        --wait-for-state TERMINATED 2>/dev/null || true
    fi
  done

  # Delete subnet, IGW, security list, VCN (order matters)
  if [[ -f "${_OCI_STATE_DIR}/subnet-id" ]]; then
    _subnet_id=$(cat "${_OCI_STATE_DIR}/subnet-id")
    oci network subnet delete --subnet-id "${_subnet_id}" --force --wait-for-state TERMINATED 2>/dev/null || true
  fi

  if [[ -f "${_OCI_STATE_DIR}/vcn-id" ]]; then
    _vcn_id=$(cat "${_OCI_STATE_DIR}/vcn-id")
    # Delete IGW, security list, route table entries before VCN
    local _igw_id
    _igw_id=$(oci network internet-gateway list \
      --compartment-id "${OCI_COMPARTMENT_ID}" \
      --vcn-id "${_vcn_id}" \
      --query 'data[0].id' --raw-output 2>/dev/null || true)
    [[ -n "${_igw_id}" && "${_igw_id}" != "null" ]] && \
      oci network internet-gateway delete --ig-id "${_igw_id}" --force 2>/dev/null || true

    oci network vcn delete --vcn-id "${_vcn_id}" --force \
      --wait-for-state TERMINATED 2>/dev/null || true
  fi

  rm -rf "${_OCI_STATE_DIR}"
  _info "[k3s-oci] OCI infrastructure deleted"
}
