# shellcheck shell=bash
# scripts/lib/providers/k3s-aws.sh — k3s on ACG AWS sandbox (single node)
#
# Provider actions:
#   deploy_cluster  — acg_provision → deploy_app_cluster → tunnel_start
#   destroy_cluster — tunnel_stop → acg_teardown

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/acg.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/shopping_cart.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/tunnel.sh"

function _provider_k3s_aws_deploy_cluster() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: CLUSTER_PROVIDER=k3s-aws ./scripts/k3d-manager deploy_cluster

Provision a single-node k3s cluster on ACG AWS sandbox:
  1. acg_provision --confirm    — EC2 + VPC + SSH config auto-update
  2. deploy_app_cluster --confirm — k3sup install + kubeconfig merge
  3. tunnel_start               — autossh tunnel from M2 Air to EC2

Milestone gate: kubectl --context ubuntu-k3s get nodes shows node Ready.

Config (env overrides):
  ACG_REGION              AWS region (default: us-west-2)
  UBUNTU_K3S_SSH_HOST     SSH host alias (default: ubuntu)
  UBUNTU_K3S_SSH_USER     SSH user (default: ubuntu)
  UBUNTU_K3S_SSH_KEY      SSH key path (default: ~/.ssh/k3d-manager-key.pem)
HELP
    return 0
  fi

  _info "[k3s-aws] Provisioning EC2 instance..."
  acg_provision --confirm || return 1

  _info "[k3s-aws] Installing k3s via k3sup..."
  deploy_app_cluster --confirm || return 1

  _info "[k3s-aws] Starting autossh tunnel..."
  tunnel_start || return 1

  _info "[k3s-aws] Cluster ready."
  _info "[k3s-aws] Verify: kubectl --context ubuntu-k3s get nodes"
}

function _provider_k3s_aws_destroy_cluster() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: CLUSTER_PROVIDER=k3s-aws ./scripts/k3d-manager destroy_cluster --confirm

Tear down the k3s-aws cluster:
  1. tunnel_stop               — stop autossh tunnel
  2. acg_teardown --confirm    — terminate EC2, remove ubuntu-k3s kubeconfig context

Requires --confirm to prevent accidental teardown.
HELP
    return 0
  fi

  if [[ "${1:-}" != "--confirm" ]]; then
    printf 'ERROR: %s\n' "[k3s-aws] destroy_cluster requires --confirm" >&2
    return 1
  fi

  _info "[k3s-aws] Stopping tunnel..."
  tunnel_stop || true

  _info "[k3s-aws] Tearing down ACG EC2..."
  acg_teardown --confirm || return 1

  _info "[k3s-aws] Cluster destroyed."
}
