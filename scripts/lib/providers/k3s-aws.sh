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
source "${SCRIPT_DIR}/plugins/gemini.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/shopping_cart.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/tunnel.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/ssm.sh"

# Probe whether the current caller may create IAM roles (side-effect-free).
# Returns 0 only when iam:CreateRole is explicitly allowed; any denial, error,
# or inability to evaluate (e.g. iam:SimulatePrincipalPolicy itself denied)
# returns non-zero so the caller falls back to the SSH tunnel.
_provider_k3s_aws_ssm_permitted() {
  local region="${ACG_REGION:-us-west-2}"
  local caller_arn source_arn decision acct role_name
  caller_arn=$(_run_command --soft -- aws sts get-caller-identity \
    --region "${region}" --query 'Arn' --output text 2>/dev/null) || return 1
  case "${caller_arn}" in
    *:assumed-role/*)
      acct=$(printf '%s' "${caller_arn}" | cut -d: -f5)
      role_name=$(printf '%s' "${caller_arn}" | sed -E 's#.*:assumed-role/([^/]+)/.*#\1#')
      source_arn="arn:aws:iam::${acct}:role/${role_name}"
      ;;
    *)
      source_arn="${caller_arn}"
      ;;
  esac
  decision=$(_run_command --soft -- aws iam simulate-principal-policy \
    --region "${region}" \
    --policy-source-arn "${source_arn}" \
    --action-names iam:CreateRole \
    --query 'EvaluationResults[0].EvalDecision' --output text 2>/dev/null) || return 1
  [[ "${decision}" == "allowed" ]]
}

# Flip the already-deployed stack to EnableSsm=true (attaches the SSM instance
# profile to running nodes with no interruption). Uses --use-previous-template
# and UsePreviousValue so no AMI/key re-derivation is needed. Idempotent: if the
# stack already has EnableSsm=true, returns 0 without an update.
_provider_k3s_aws_enable_ssm_stack() {
  local region="${ACG_REGION:-us-west-2}" current
  current=$(_run_command --soft -- aws cloudformation describe-stacks \
    --region "${region}" --stack-name "${_ACG_CF_STACK_NAME}" \
    --query "Stacks[0].Parameters[?ParameterKey=='EnableSsm'].ParameterValue" \
    --output text 2>/dev/null)
  if [[ "${current}" == "true" ]]; then
    _info "[k3s-aws] Stack already has EnableSsm=true — SSM profile present"
    return 0
  fi
  _info "[k3s-aws] Updating stack ${_ACG_CF_STACK_NAME} with EnableSsm=true..."
  _run_command --soft -- aws cloudformation update-stack \
    --region "${region}" \
    --stack-name "${_ACG_CF_STACK_NAME}" \
    --use-previous-template \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters \
      ParameterKey=EnableSsm,ParameterValue=true \
      ParameterKey=KeyName,UsePreviousValue=true \
      ParameterKey=AllowedCidr,UsePreviousValue=true \
      ParameterKey=InstanceType,UsePreviousValue=true \
      ParameterKey=AmiId,UsePreviousValue=true >/dev/null 2>&1 || return 1
  _run_command --soft -- aws cloudformation wait stack-update-complete \
    --region "${region}" --stack-name "${_ACG_CF_STACK_NAME}" || return 1
}

# Block until the SSM agent registers the instance (PingStatus Online), so the
# subsequent ssm_tunnel does not race the profile attachment. Times out at 150s.
_provider_k3s_aws_wait_ssm_registered() {
  local instance_id="$1" region="${ACG_REGION:-us-west-2}" attempts=0
  _info "[k3s-aws] Waiting for SSM agent to register ${instance_id}..."
  until [[ "$(_run_command --soft -- aws ssm describe-instance-information \
      --region "${region}" \
      --filters "Key=InstanceIds,Values=${instance_id}" \
      --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null)" == "Online" ]]; do
    (( attempts++ ))
    if (( attempts >= 30 )); then
      _err "[k3s-aws] SSM agent did not register ${instance_id} within 150s"
      return 1
    fi
    sleep 5
  done
  _info "[k3s-aws] SSM agent online for ${instance_id}"
}

# Decide tunnel mode once, after the stack exists. Honors an explicit
# K3S_AWS_SSM_ENABLED; otherwise probes iam:CreateRole and, when permitted,
# enables SSM on the stack. Any failure degrades to the SSH tunnel.
_provider_k3s_aws_autoselect_tunnel_mode() {
  if [[ -n "${K3S_AWS_SSM_ENABLED:-}" ]]; then
    _info "[k3s-aws] Tunnel mode explicitly set (K3S_AWS_SSM_ENABLED=${K3S_AWS_SSM_ENABLED}) — skipping auto-detect"
    return 0
  fi
  _info "[k3s-aws] Auto-detecting tunnel mode (probing iam:CreateRole)..."
  if _provider_k3s_aws_ssm_permitted && _provider_k3s_aws_enable_ssm_stack; then
    export K3S_AWS_SSM_ENABLED=true
    _info "[k3s-aws] iam:CreateRole permitted + SSM profile attached — using SSM port-forwarding (no inbound SSH)"
  else
    export K3S_AWS_SSM_ENABLED=false
    _info "[k3s-aws] SSM unavailable (iam:CreateRole denied/undetectable or stack update failed) — using SSH tunnel (autossh)"
  fi
}

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
  _cf_stack_status=$(_run_command --soft -- aws cloudformation describe-stacks \
    --region "${ACG_REGION}" --stack-name "${_ACG_CF_STACK_NAME}" \
    --query 'Stacks[0].StackStatus' --output text 2>/dev/null || true)
  case "${_cf_stack_status}" in
    CREATE_COMPLETE|UPDATE_COMPLETE|UPDATE_ROLLBACK_COMPLETE)
      _info "[k3s-aws] CloudFormation stack is healthy (${_cf_stack_status}) — reusing without recreate"
      acg_provision --confirm || return 1
      ;;
    ROLLBACK_COMPLETE|CREATE_FAILED|ROLLBACK_FAILED|UPDATE_ROLLBACK_FAILED|DELETE_FAILED)
      _info "[k3s-aws] CloudFormation stack is in broken state (${_cf_stack_status}) — recreating"
      acg_provision --confirm --recreate || return 1
      ;;
    *)
      _info "[k3s-aws] CloudFormation stack not found or unknown state (${_cf_stack_status:-none}) — creating"
      acg_provision --confirm || return 1
      ;;
  esac

  _provider_k3s_aws_autoselect_tunnel_mode

  local _ready_nodes
  _ready_nodes=$(kubectl get nodes --context ubuntu-k3s --no-headers 2>/dev/null \
    | grep -c " Ready" || true)
  if [[ "${_ready_nodes}" -ge 3 ]]; then
    _info "[k3s-aws] k3s nodes already Ready (${_ready_nodes}/3) — skipping deploy_app_cluster"
  else
    _info "[k3s-aws] Installing k3s server + joining agents..."
    UBUNTU_K3S_AGENT_HOSTS="ubuntu-1,ubuntu-2" deploy_app_cluster --confirm || return 1
  fi

  if [[ "${K3S_AWS_SSM_ENABLED:-false}" == "true" ]]; then
    _info "[k3s-aws] Starting SSM port-forwarding tunnel (k3s API :6443)..."
    local _server_id
    _server_id=$(_ssm_get_instance_id "${UBUNTU_K3S_SSH_HOST:-ubuntu}") || return 1
    _provider_k3s_aws_wait_ssm_registered "${_server_id}" || return 1
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
    disown "${_watcher_pid}"
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
