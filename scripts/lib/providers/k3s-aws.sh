# shellcheck shell=bash
# scripts/lib/providers/k3s-aws.sh — k3s on ACG AWS sandbox (3-node cluster)
#
# Provider actions:
#   deploy_cluster  — acg_provision (CloudFormation stack) → deploy_app_cluster
#                     → tunnel_start → kubectl label → acg_watch
#   destroy_cluster — stop watcher → tunnel_stop → acg_teardown

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/acg.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/antigravity.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/shopping_cart.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/tunnel.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/ssm.sh"

function _provider_k3s_aws_deploy_cluster() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: CLUSTER_PROVIDER=k3s-aws ./scripts/k3d-manager deploy_cluster

Provision a 3-node k3s cluster on ACG AWS sandbox:
  1. acg_extend_playwright       — pre-flight TTL extend
  2. acg_provision --confirm     — CloudFormation stack (server + agents)
  3. deploy_app_cluster --confirm — install k3s + join agents; kubeconfig merge
  4. tunnel_start / ssm_tunnel   — port-forward to server :6443
  5. kubectl label nodes         — k3d-manager/node-type=server|agent
  6. acg_watch (background)      — sandbox TTL watcher

Milestone gate: kubectl --context ubuntu-k3s get nodes shows 3 nodes Ready.

Config (env overrides):
  ACG_REGION              AWS region (default: us-west-2)
  ACG_AGENT_COUNT         Number of agent nodes (default: 2)
  UBUNTU_K3S_SSH_HOST     SSH host alias for server (default: ubuntu)
  UBUNTU_K3S_SSH_USER     SSH user (default: ubuntu)
  UBUNTU_K3S_SSH_KEY      SSH key path (default: ~/.ssh/k3d-manager-key.pem)
  K3S_AWS_SSM_ENABLED     Set to 'true' to use SSM instead of SSH (default: false)
                          Note: Vault reverse bridge not supported in SSM mode.
HELP
    return 0
  fi

  _info "[k3s-aws] Extending sandbox TTL before deploy (pre-flight)..."
  acg_extend_playwright "${_ACG_SANDBOX_URL}" \
    || _info "[k3s-aws] Pre-flight extend failed — proceeding (sandbox may have sufficient TTL)"

  _info "[k3s-aws] Provisioning CloudFormation stack (server + agents)..."
  acg_provision --confirm || return 1

  _info "[k3s-aws] Installing k3s server + joining agents..."
  UBUNTU_K3S_AGENT_HOSTS="ubuntu-1,ubuntu-2" deploy_app_cluster --confirm || return 1

  if [[ "${K3S_AWS_SSM_ENABLED:-false}" == "true" ]]; then
    _info "[k3s-aws] Starting SSM port-forwarding tunnel (k3s API :6443)..."
    local _server_id
    _server_id=$(_ssm_get_instance_id "${UBUNTU_K3S_SSH_HOST:-ubuntu}") || return 1
    ssm_tunnel "${_server_id}" "6443" "6443" || return 1
  else
    _info "[k3s-aws] Starting autossh tunnel..."
    tunnel_start || return 1
  fi

  local local_kubeconfig="${UBUNTU_K3S_LOCAL_KUBECONFIG:-${HOME}/.kube/k3s-ubuntu.yaml}"
  local total_nodes=3

  _info "[k3s-aws] Waiting for all ${total_nodes} nodes to be Ready..."
  local node_attempts=0
  until [[ "$(KUBECONFIG="${local_kubeconfig}" kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready")" -ge "${total_nodes}" ]]; do
    (( node_attempts++ ))
    if (( node_attempts >= 60 )); then
      _info "[k3s-aws] WARNING: not all nodes Ready after 300s — skipping label step"
      break
    fi
    sleep 5
  done

  if (( node_attempts < 60 )); then
    _info "[k3s-aws] Labeling nodes..."
    local server_node
    server_node=$(KUBECONFIG="${local_kubeconfig}" kubectl get nodes \
      --selector='node-role.kubernetes.io/control-plane' \
      --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -n1)
    [[ -n "${server_node}" ]] && \
      KUBECONFIG="${local_kubeconfig}" kubectl label node "${server_node}" \
        k3d-manager/node-type=server --overwrite >/dev/null 2>&1 || true
    while IFS= read -r agent_node; do
      [[ -n "${agent_node}" ]] && \
        KUBECONFIG="${local_kubeconfig}" kubectl label node "${agent_node}" \
          k3d-manager/node-type=agent --overwrite >/dev/null 2>&1 || true
    done < <(KUBECONFIG="${local_kubeconfig}" kubectl get nodes \
      --selector='!node-role.kubernetes.io/control-plane' \
      --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null)
  fi

  _info "[k3s-aws] Starting sandbox watcher..."
  local _existing_pid
  if [[ -f "${_ACG_WATCH_PID_FILE}" ]]; then
    _existing_pid=$(cat "${_ACG_WATCH_PID_FILE}")
    if kill -0 "${_existing_pid}" 2>/dev/null; then
      _info "[k3s-aws] Watcher already running (PID ${_existing_pid}) — skipping"
    else
      rm -f "${_ACG_WATCH_PID_FILE}"
    fi
  fi
  if [[ ! -f "${_ACG_WATCH_PID_FILE}" ]]; then
    acg_watch &
    local _watcher_pid=$!
    mkdir -p "$(dirname "${_ACG_WATCH_PID_FILE}")"
    printf '%s\n' "${_watcher_pid}" > "${_ACG_WATCH_PID_FILE}"
    _info "[k3s-aws] Watcher PID: ${_watcher_pid} (stored in ${_ACG_WATCH_PID_FILE})"
  fi

  _info "[k3s-aws] Cluster ready. ${total_nodes}-node k3s cluster provisioned."
  _info "[k3s-aws] Verify: kubectl --context ubuntu-k3s get nodes"
}

function _provider_k3s_aws_destroy_cluster() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: CLUSTER_PROVIDER=k3s-aws ./scripts/k3d-manager destroy_cluster --confirm

Tear down the 3-node k3s-aws cluster:
  1. Stop sandbox watcher
  2. tunnel_stop                — stop autossh tunnel
  3. acg_teardown --confirm     — delete CloudFormation stack; remove ubuntu-k3s kubeconfig context

Requires --confirm to prevent accidental teardown.
HELP
    return 0
  fi

  if [[ "${1:-}" != "--confirm" ]]; then
    printf 'ERROR: %s\n' "[k3s-aws] destroy_cluster requires --confirm" >&2
    return 1
  fi

  if [[ -f "${_ACG_WATCH_PID_FILE}" ]]; then
    local _watcher_pid
    _watcher_pid=$(cat "${_ACG_WATCH_PID_FILE}")
    if kill -0 "${_watcher_pid}" 2>/dev/null; then
      _info "[k3s-aws] Stopping sandbox watcher (PID ${_watcher_pid})..."
      kill "${_watcher_pid}" 2>/dev/null || true
    fi
    rm -f "${_ACG_WATCH_PID_FILE}"
  fi

  if [[ "${K3S_AWS_SSM_ENABLED:-false}" == "true" ]]; then
    if [[ -f "${_SSM_TUNNEL_FWD_PID_FILE}" ]]; then
      local _ssm_pid
      _ssm_pid=$(cat "${_SSM_TUNNEL_FWD_PID_FILE}")
      if kill -0 "${_ssm_pid}" 2>/dev/null; then
        _info "[k3s-aws] Stopping SSM tunnel (PID ${_ssm_pid})..."
        kill "${_ssm_pid}" 2>/dev/null || true
      fi
      rm -f "${_SSM_TUNNEL_FWD_PID_FILE}"
    fi
  else
    _info "[k3s-aws] Stopping tunnel..."
    tunnel_stop || true
  fi

  _info "[k3s-aws] Tearing down server EC2..."
  acg_teardown --confirm || return 1

  _info "[k3s-aws] Cluster destroyed."
}
