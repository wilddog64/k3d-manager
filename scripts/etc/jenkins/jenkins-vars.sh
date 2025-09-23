export NAMESPACE="jenkins"
export JENKINS_HOME_PATH="$SCRIPT_DIR/storage/jenkins_home"

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
export JENKINS_CERT_ROTATOR_IMAGE="${JENKINS_CERT_ROTATOR_IMAGE:-docker.io/bitnami/kubectl:1.30.2}"
export JENKINS_CERT_ROTATOR_VAULT_ROLE="${JENKINS_CERT_ROTATOR_VAULT_ROLE:-jenkins-cert-rotator}"
