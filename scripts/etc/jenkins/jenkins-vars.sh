export NAMESPACE="jenkins"
export JENKINS_HOME_PATH="$SCRIPT_DIR/storage/jenkins_home"

# Optional: immediately mint a cert to a K8s tls secret via Istio
export VAULT_PKI_ISSUE_SECRET="${VAULT_PKI_ISSUE_SECRET:-0}"   # 1 to emit a tls Secret
export VAULT_PKI_SECRET_NS="${VAULT_PKI_SECRET_NS:-istio-system}"
export VAULT_PKI_SECRET_NAME="${VAULT_PKI_SECRET_NAME:-jenkins-tls}"
export VAULT_PKI_LEAF_HOST="${VAULT_PKI_LEAF_HOST:-jenkins.dev.local.me}" # CN/SAN to issue
