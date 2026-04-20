# shellcheck shell=bash
# scripts/lib/providers/k3s-gcp.sh — k3s on ACG GCP sandbox (v1.1.0: credential flow only)
#
# Provider actions:
#   deploy_cluster  — placeholder; full GCP provisioning is not yet implemented
#   destroy_cluster — placeholder; not yet implemented

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/gcp.sh"

function _provider_k3s_gcp_deploy_cluster() {
  _info "[k3s-gcp] GCP cluster provisioning is not yet implemented (v1.1.0 recovery scope: credential flow only)."
  _info "[k3s-gcp] acg-up will exit after this step — use 'kubectl get nodes' to verify once a cluster is available."
}

function _provider_k3s_gcp_destroy_cluster() {
  _info "[k3s-gcp] GCP cluster teardown is not yet implemented."
}
