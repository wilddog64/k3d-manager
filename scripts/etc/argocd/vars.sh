# Argo CD configuration variables

# Namespace and Helm configuration
export ARGOCD_NAMESPACE="argocd"
export ARGOCD_HELM_RELEASE="argocd"
export ARGOCD_HELM_REPO_NAME="argo"
export ARGOCD_HELM_REPO_URL="https://argoproj.github.io/argo-helm"
export ARGOCD_HELM_CHART_REF="argo/argo-cd"
export ARGOCD_HELM_CHART_VERSION=""  # Empty = latest

# Deployment Feature Flags
export ARGOCD_LDAP_ENABLED="${ARGOCD_LDAP_ENABLED:-0}"    # 0 = disabled by default, use --enable-ldap to deploy
export ARGOCD_VAULT_ENABLED="${ARGOCD_VAULT_ENABLED:-0}"  # 0 = disabled by default, use --enable-vault to deploy

# Istio ingress configuration
export ARGOCD_VIRTUALSERVICE_HOST="${ARGOCD_VIRTUALSERVICE_HOST:-argocd.dev.local.me}"
export ARGOCD_VIRTUALSERVICE_GATEWAY="${ARGOCD_VIRTUALSERVICE_GATEWAY:-istio-system/default-gateway}"

# LDAP/Dex configuration (for LDAP authentication)
export ARGOCD_LDAP_HOST="${ARGOCD_LDAP_HOST:-openldap-openldap-bitnami.directory.svc.cluster.local}"
export ARGOCD_LDAP_PORT="${ARGOCD_LDAP_PORT:-389}"
export ARGOCD_LDAP_BASE_DN="${ARGOCD_LDAP_BASE_DN:-dc=home,dc=org}"
export ARGOCD_LDAP_BIND_DN="${ARGOCD_LDAP_BIND_DN:-cn=ldap-admin,dc=home,dc=org}"
export ARGOCD_LDAP_USER_SEARCH_BASE="${ARGOCD_LDAP_USER_SEARCH_BASE:-ou=users}"
export ARGOCD_LDAP_USER_SEARCH_FILTER="${ARGOCD_LDAP_USER_SEARCH_FILTER:-'(cn={0})'}"
export ARGOCD_LDAP_GROUP_SEARCH_BASE="${ARGOCD_LDAP_GROUP_SEARCH_BASE:-ou=groups}"
export ARGOCD_LDAP_GROUP_SEARCH_FILTER="${ARGOCD_LDAP_GROUP_SEARCH_FILTER:-'(|(memberUid={1})(member={0})(uniqueMember={0}))'}"

# Vault/ESO integration for admin credentials
export ARGOCD_ESO_SERVICE_ACCOUNT="${ARGOCD_ESO_SERVICE_ACCOUNT:-eso-argocd-sa}"
export ARGOCD_ESO_SECRETSTORE="${ARGOCD_ESO_SECRETSTORE:-vault-kv-store}"
export ARGOCD_ESO_ROLE="${ARGOCD_ESO_ROLE:-eso-argocd-admin}"
export ARGOCD_ESO_API_VERSION="${ARGOCD_ESO_API_VERSION:-external-secrets.io/v1}"
export ARGOCD_VAULT_KV_MOUNT="${ARGOCD_VAULT_KV_MOUNT:-secret}"
export ARGOCD_ADMIN_SECRET_NAME="${ARGOCD_ADMIN_SECRET_NAME:-argocd-admin-secret}"
export ARGOCD_ADMIN_VAULT_PATH="${ARGOCD_ADMIN_VAULT_PATH:-argocd/admin}"
export ARGOCD_ADMIN_PASSWORD_KEY="${ARGOCD_ADMIN_PASSWORD_KEY:-password}"
export ARGOCD_VAULT_POLICY_PREFIX="${ARGOCD_VAULT_POLICY_PREFIX:-argocd/admin}"

# LDAP secret (for Dex connector)
export ARGOCD_LDAP_SECRET_NAME="${ARGOCD_LDAP_SECRET_NAME:-argocd-ldap-secret}"
export ARGOCD_LDAP_VAULT_PATH="${ARGOCD_LDAP_VAULT_PATH:-ldap/openldap-admin}"
export ARGOCD_LDAP_BINDDN_KEY="${ARGOCD_LDAP_BINDDN_KEY:-LDAP_BIND_DN}"
export ARGOCD_LDAP_PASSWORD_KEY="${ARGOCD_LDAP_PASSWORD_KEY:-LDAP_ADMIN_PASSWORD}"

# Argo CD server configuration
export ARGOCD_SERVER_INSECURE="${ARGOCD_SERVER_INSECURE:-true}"  # Run behind Istio, so insecure=true
export ARGOCD_SERVER_REPLICAS="${ARGOCD_SERVER_REPLICAS:-1}"
export ARGOCD_REPO_SERVER_REPLICAS="${ARGOCD_REPO_SERVER_REPLICAS:-1}"
export ARGOCD_APPLICATIONSET_REPLICAS="${ARGOCD_APPLICATIONSET_REPLICAS:-1}"

# RBAC defaults
export ARGOCD_RBAC_DEFAULT_POLICY="${ARGOCD_RBAC_DEFAULT_POLICY:-role:readonly}"  # Default policy for users
export ARGOCD_RBAC_ADMIN_GROUP="${ARGOCD_RBAC_ADMIN_GROUP:-cn=admins,ou=groups,dc=home,dc=org}"
