# cert-manager configuration variables

# Helm chart configuration
export CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
export CERT_MANAGER_HELM_RELEASE="${CERT_MANAGER_HELM_RELEASE:-cert-manager}"
export CERT_MANAGER_HELM_REPO_NAME="${CERT_MANAGER_HELM_REPO_NAME:-jetstack}"
export CERT_MANAGER_HELM_REPO_URL="${CERT_MANAGER_HELM_REPO_URL:-https://charts.jetstack.io}"
export CERT_MANAGER_HELM_CHART_REF="${CERT_MANAGER_HELM_CHART_REF:-jetstack/cert-manager}"
export CERT_MANAGER_HELM_CHART_VERSION="${CERT_MANAGER_HELM_CHART_VERSION:-v1.20.0}"

# ACME configuration
export ACME_EMAIL="${ACME_EMAIL:-}"
export ACME_STAGING_SERVER="${ACME_STAGING_SERVER:-https://acme-staging-v02.api.letsencrypt.org/directory}"
export ACME_PRODUCTION_SERVER="${ACME_PRODUCTION_SERVER:-https://acme-v02.api.letsencrypt.org/directory}"
export ACME_INGRESS_CLASS="${ACME_INGRESS_CLASS:-istio}"

# ClusterIssuer names
export CERT_MANAGER_STAGING_ISSUER="${CERT_MANAGER_STAGING_ISSUER:-letsencrypt-staging}"
export CERT_MANAGER_PRODUCTION_ISSUER="${CERT_MANAGER_PRODUCTION_ISSUER:-letsencrypt-production}"

# HTTP-01 Gateway configuration
export CERT_MANAGER_HTTP_GATEWAY="${CERT_MANAGER_HTTP_GATEWAY:-cert-manager-http-gw}"
export CERT_MANAGER_HTTP_GATEWAY_NS="${CERT_MANAGER_HTTP_GATEWAY_NS:-istio-system}"
