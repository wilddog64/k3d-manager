# shellcheck shell=bash
# scripts/lib/providers/k3s-aws.sh — k3s on ACG AWS sandbox (3-node cluster)
#
# Provider actions:
#   deploy_cluster  — acg_provision (server) → _acg_provision_agents → deploy_app_cluster
#                     → tunnel_start → kubectl label → acg_watch
#   destroy_cluster — stop watcher → _acg_teardown_agents → tunnel_stop → acg_teardown

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/acg.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/antigravity.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/shopping_cart.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/tunnel.sh"

function _provider_k3s_aws_deploy_cluster() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: CLUSTER_PROVIDER=k3s-aws ./scripts/k3d-manager deploy_cluster

Provision a 3-node k3s cluster on ACG AWS sandbox:
  1. antigravity_acg_extend      — pre-flight TTL extend
  2. acg_provision --confirm     — server EC2 (k3d-manager-ubuntu / ubuntu)
  3. _acg_provision_agents       — agent EC2s (k3d-manager-ubuntu-1/2 / ubuntu-1/2)
  4. deploy_app_cluster --confirm — k3sup install server + join agents; kubeconfig merge
  5. tunnel_start                — autossh tunnel M2 Air → server :6443
  6. kubectl label nodes         — k3d-manager/node-type=server|agent
  7. acg_watch (background)      — sandbox TTL watcher

Milestone gate: kubectl --context ubuntu-k3s get nodes shows 3 nodes Ready.

Config (env overrides):
  ACG_REGION              AWS region (default: us-west-2)
  ACG_AGENT_COUNT         Number of agent nodes (default: 2)
  UBUNTU_K3S_SSH_HOST     SSH host alias for server (default: ubuntu)
  UBUNTU_K3S_SSH_USER     SSH user (default: ubuntu)
  UBUNTU_K3S_SSH_KEY      SSH key path (default: ~/.ssh/k3d-manager-key.pem)
HELP
    return 0
  fi

  _info "[k3s-aws] Extending sandbox TTL before deploy (pre-flight)..."
  antigravity_acg_extend "${_ACG_SANDBOX_URL}" \
    || _info "[k3s-aws] Pre-flight extend failed — proceeding (sandbox may have sufficient TTL)"

  _info "[k3s-aws] Provisioning server EC2..."
  acg_provision --confirm || return 1

  _info "[k3s-aws] Provisioning agent EC2s..."
  _acg_provision_agents || return 1

  _info "[k3s-aws] Installing k3s server + joining agents..."
  UBUNTU_K3S_AGENT_HOSTS="ubuntu-1,ubuntu-2" deploy_app_cluster --confirm || return 1

  _info "[k3s-aws] Starting autossh tunnel..."
  tunnel_start || return 1

  local local_kubeconfig="${UBUNTU_K3S_LOCAL_KUBECONFIG:-${HOME}/.kube/k3s-ubuntu.yaml}"
  local agent_count="${ACG_AGENT_COUNT:-2}"
  local total_nodes=$(( agent_count + 1 ))

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
  2. _acg_teardown_agents       — terminate agent EC2s (k3d-manager-ubuntu-1/2)
  3. tunnel_stop                — stop autossh tunnel
  4. acg_teardown --confirm     — terminate server EC2; remove ubuntu-k3s kubeconfig context

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

  _info "[k3s-aws] Terminating agent nodes..."
  _acg_teardown_agents

  _info "[k3s-aws] Stopping tunnel..."
  tunnel_stop || true

  _info "[k3s-aws] Tearing down server EC2..."
  acg_teardown --confirm || return 1

  _info "[k3s-aws] Cluster destroyed."
}
