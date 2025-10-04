export ALLOW_EMPTY_VARS=(VAULT_NAMESPACE bin)
export JENKINS_NAMESPACE="jenkins"
export VAULT_ENABLE_INJECTOR="${VAULT_ENABLE_INJECTOR:-true}"
export JENKINS_ENABLE_VAULT_AGENT_INJECTOR="${JENKINS_ENABLE_VAULT_AGENT_INJECTOR:-1}"

# Optional: immediately mint a cert to a K8s tls secret via Istio
export VAULT_PKI_ISSUE_SECRET="${VAULT_PKI_ISSUE_SECRET:-1}"   # 1 to emit a tls Secret
export VAULT_PKI_SECRET_NS="${VAULT_PKI_SECRET_NS:-istio-system}"
export VAULT_PKI_SECRET_NAME="${VAULT_PKI_SECRET_NAME:-jenkins-tls}"
export VAULT_PKI_LEAF_HOST="${VAULT_PKI_LEAF_HOST:-jenkins.dev.local.me}" # CN/SAN to issue
export JENKINS_VIRTUALSERVICE_HOSTS="${JENKINS_VIRTUALSERVICE_HOSTS:-}"    # Optional override for Istio hosts list

# Optional: configure cert rotation via a K8s CronJob
export JENKINS_CERT_ROTATOR_ENABLED="${JENKINS_CERT_ROTATOR_ENABLED:-1}"   # 1 to manage cert rotation
export JENKINS_CERT_ROTATOR_SCHEDULE="${JENKINS_CERT_ROTATOR_SCHEDULE:-0 */12 * * *}"
export JENKINS_CERT_ROTATOR_RENEW_BEFORE="${JENKINS_CERT_ROTATOR_RENEW_BEFORE:-432000}"
export JENKINS_CERT_ROTATOR_NAME="${JENKINS_CERT_ROTATOR_NAME:-jenkins-cert-rotator}"
export JENKINS_CERT_ROTATOR_SERVICE_ACCOUNT="${JENKINS_CERT_ROTATOR_SERVICE_ACCOUNT:-jenkins-cert-rotator}"
export JENKINS_CERT_ROTATOR_IMAGE="${JENKINS_CERT_ROTATOR_IMAGE:-docker.io/google/cloud-sdk:slim}"
export JENKINS_CERT_ROTATOR_VAULT_ROLE="${JENKINS_CERT_ROTATOR_VAULT_ROLE:-jenkins-cert-rotator}"
export JENKINS_CERT_ROTATOR_ALT_NAMES="jenkins.dev.local.me,jenkins.dev.k3d.internal"
export JENKINS_VIRTUALSERVICE_HOSTS="${JENKINS_CERT_ROTATOR_ALT_NAMES}"
export JENKINS_CERT_ROTATOR_SCRIPT_B64="$(base64 < "${SCRIPT_DIR}/etc/jenkins/cert-rotator.sh" | tr -d '\n')"
export JENKINS_CERT_ROTATOR_VAULT_PKI_LIB_B64="$(base64 < "${SCRIPT_DIR}/lib/vault_pki.sh" | tr -d '\n')"

# Vault PKI config
export VAULT_ADDR="https://vault.vault.svc.cluster.local:8200"
export VAULT_AUTH_PATH="pki"
export VAULT_ROLE="jenkins-cert-rotator"
export VAULT_PKI_ROLE_TTL="720h"
export VAULT_NAMESPACE=""
export VAULT_SKIP_VERIFY="true"  # true if using TLS between Vault and Jenkins
export VAULT_CACERT="/etc/ssl/certs/vault-ca.pem"

# roator specific
export VAULT_PKI_SECRET_NS="istio-system"
export VAULT_PKI_PATH="${VAULT_PKI_PATH:-pki}"
export VAULT_PKI_ROLE="${VAULT_PKI_ROLE:-jenkins-tls}"
