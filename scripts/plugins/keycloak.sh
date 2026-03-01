#!/usr/bin/env bash
# shellcheck disable=SC2016
# scripts/plugins/keycloak.sh — Bitnami Keycloak deployment plugin

VAULT_PLUGIN="$PLUGINS_DIR/vault.sh"
if [[ -r "$VAULT_PLUGIN" ]]; then
   # shellcheck disable=SC1090
   source "$VAULT_PLUGIN"
fi

ESO_PLUGIN="$PLUGINS_DIR/eso.sh"
if [[ -r "$ESO_PLUGIN" ]]; then
   # shellcheck disable=SC1090
   source "$ESO_PLUGIN"
fi

VAULT_VARS_FILE="$SCRIPT_DIR/etc/vault/vars.sh"
if [[ -r "$VAULT_VARS_FILE" ]]; then
   # shellcheck disable=SC1090
   source "$VAULT_VARS_FILE"
fi

KEYCLOAK_CONFIG_DIR="$SCRIPT_DIR/etc/keycloak"
KEYCLOAK_VARS_FILE="$KEYCLOAK_CONFIG_DIR/vars.sh"
if [[ -r "$KEYCLOAK_VARS_FILE" ]]; then
   # shellcheck disable=SC1090
   source "$KEYCLOAK_VARS_FILE"
fi

: "${KEYCLOAK_NAMESPACE:=identity}"
: "${KEYCLOAK_HELM_RELEASE:=keycloak}"
: "${KEYCLOAK_HELM_REPO_NAME:=bitnami}"
: "${KEYCLOAK_HELM_REPO_URL:=https://charts.bitnami.com/bitnami}"
: "${KEYCLOAK_HELM_CHART_REF:=bitnami/keycloak}"
: "${KEYCLOAK_VIRTUALSERVICE_HOST:=keycloak.dev.local.me}"
: "${KEYCLOAK_SERVICE_PORT:=8080}"
: "${KEYCLOAK_ADMIN_SECRET_NAME:=keycloak-admin-secret}"
: "${KEYCLOAK_ADMIN_PASSWORD_KEY:=password}"
: "${KEYCLOAK_VAULT_KV_MOUNT:=secret}"
: "${KEYCLOAK_ADMIN_VAULT_PATH:=keycloak/admin}"
: "${KEYCLOAK_ESO_SERVICE_ACCOUNT:=eso-keycloak-sa}"
: "${KEYCLOAK_ESO_SECRETSTORE:=keycloak-vault-store}"
: "${KEYCLOAK_ESO_ROLE:=eso-keycloak-admin}"
: "${KEYCLOAK_ESO_API_VERSION:=external-secrets.io/v1}"
: "${KEYCLOAK_LDAP_SECRET_NAME:=keycloak-ldap-secret}"
: "${KEYCLOAK_LDAP_VAULT_PATH:=ldap/openldap-admin}"
: "${KEYCLOAK_LDAP_BINDDN_KEY:=LDAP_BIND_DN}"
: "${KEYCLOAK_LDAP_PASSWORD_KEY:=LDAP_ADMIN_PASSWORD}"
: "${KEYCLOAK_LDAP_HOST:=openldap-openldap-bitnami.identity.svc.cluster.local}"
: "${KEYCLOAK_LDAP_PORT:=389}"
: "${KEYCLOAK_LDAP_BASE_DN:=dc=home,dc=org}"
: "${KEYCLOAK_LDAP_USERS_DN:=ou=users,dc=home,dc=org}"
: "${KEYCLOAK_REALM_NAME:=home}"
: "${KEYCLOAK_REALM_DISPLAY_NAME:=Home}"

function deploy_keycloak() {
   if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      cat <<'HELP'
Usage: deploy_keycloak [options]

Deploy the Bitnami Keycloak chart with optional LDAP + Vault integration.

Options:
   --enable-ldap     Configure LDAP federation (requires Vault secret)
   --enable-vault    Seed admin password in Vault via ESO
   --skip-istio      Skip Istio VirtualService creation
   -h, --help        Show this help message
HELP
      return 0
   fi

   if [[ "${CLUSTER_ROLE:-infra}" == "app" ]]; then
      _info "[keycloak] CLUSTER_ROLE=app — skipping deploy_keycloak"
      return 0
   fi

   local enable_ldap=0 enable_vault=0 skip_istio=0
   local config_cli_enabled="${KEYCLOAK_CONFIG_CLI_ENABLED:-false}"

   while [[ $# -gt 0 ]]; do
      case "$1" in
         --enable-ldap) enable_ldap=1; config_cli_enabled="true"; shift ;;
         --enable-vault) enable_vault=1; shift ;;
         --skip-istio) skip_istio=1; shift ;;
         *)
            _err "[keycloak] Unknown option: $1"
            return 1
            ;;
      esac
   done

   _info "[keycloak] Deploying to namespace: $KEYCLOAK_NAMESPACE"
   _kubectl create namespace "$KEYCLOAK_NAMESPACE" --dry-run=client -o yaml | _kubectl apply -f - >/dev/null

   _info "[keycloak] Adding Helm repository: $KEYCLOAK_HELM_REPO_NAME"
   _helm repo add "$KEYCLOAK_HELM_REPO_NAME" "$KEYCLOAK_HELM_REPO_URL"
   _helm repo update >/dev/null 2>&1

   if (( enable_vault || enable_ldap )); then
      _keycloak_setup_vault_policies
      envsubst < "$KEYCLOAK_CONFIG_DIR/secretstore.yaml.tmpl" | _kubectl apply -f - >/dev/null
   fi

   if (( enable_vault )); then
      _keycloak_seed_vault_admin_secret
      envsubst < "$KEYCLOAK_CONFIG_DIR/externalsecret-admin.yaml.tmpl" | _kubectl apply -f - >/dev/null
      if ! _kubectl -n "$KEYCLOAK_NAMESPACE" wait --for=condition=Ready --timeout=60s externalsecret/"$KEYCLOAK_ADMIN_SECRET_NAME" 2>/dev/null; then
         _warn "[keycloak] Timeout waiting for admin ExternalSecret"
      fi
   else
      _keycloak_ensure_admin_secret
   fi

   if (( enable_ldap )); then
      envsubst < "$KEYCLOAK_CONFIG_DIR/externalsecret-ldap.yaml.tmpl" | _kubectl apply -f - >/dev/null
      if ! _kubectl -n "$KEYCLOAK_NAMESPACE" wait --for=condition=Ready --timeout=60s externalsecret/"$KEYCLOAK_LDAP_SECRET_NAME" 2>/dev/null; then
         _warn "[keycloak] Timeout waiting for LDAP ExternalSecret"
      fi
      _keycloak_apply_realm_configmap
   fi

   local values_file
   values_file=$(mktemp -t keycloak-values.XXXXXX.yaml)
   trap '$(_cleanup_trap_command "$values_file")' EXIT
   KEYCLOAK_CONFIG_CLI_ENABLED="$config_cli_enabled"
   envsubst '$KEYCLOAK_ADMIN_USERNAME $KEYCLOAK_ADMIN_SECRET_NAME $KEYCLOAK_ADMIN_PASSWORD_KEY $KEYCLOAK_NAMESPACE $KEYCLOAK_SERVICE_PORT $KEYCLOAK_VIRTUALSERVICE_HOST $KEYCLOAK_CONFIG_CLI_ENABLED' \
      < "$KEYCLOAK_CONFIG_DIR/values.yaml.tmpl" > "$values_file"

   _info "[keycloak] Installing/Upgrading Helm release"
   _helm upgrade --install -n "$KEYCLOAK_NAMESPACE" "$KEYCLOAK_HELM_RELEASE" "$KEYCLOAK_HELM_CHART_REF" --values "$values_file"

   if ! _kubectl -n "$KEYCLOAK_NAMESPACE" rollout status statefulset/keycloak --timeout=300s 2>/dev/null; then
      _warn "[keycloak] Timeout waiting for Keycloak StatefulSet"
   fi

   if (( ! skip_istio )); then
      envsubst < "$KEYCLOAK_CONFIG_DIR/virtualservice.yaml.tmpl" | _kubectl apply -f - >/dev/null
      _info "[keycloak] Istio VirtualService applied for host $KEYCLOAK_VIRTUALSERVICE_HOST"
   fi

   _info "[keycloak] Deployment complete"
   _info "[keycloak] UI available at: https://$KEYCLOAK_VIRTUALSERVICE_HOST"
   if (( enable_vault )); then
      _info "[keycloak] Admin password stored in secret '$KEYCLOAK_ADMIN_SECRET_NAME'"
   fi
}

function _keycloak_seed_vault_admin_secret() {
   local ns="${VAULT_NS_DEFAULT:-vault}"
   local release="${VAULT_RELEASE_DEFAULT:-vault}"
   local pod="${release}-0"
   local secret_path="${KEYCLOAK_VAULT_KV_MOUNT}/${KEYCLOAK_ADMIN_VAULT_PATH}"

   if _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- \
         vault kv get -format=json "$secret_path" >/dev/null 2>&1; then
      _info "[keycloak] Vault admin secret already exists at ${secret_path}, skipping"
      return 0
   fi

   _info "[keycloak] Seeding Keycloak admin password in Vault"
   local password
   password=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#%^&*' </dev/urandom | head -c 24)

   _vault_login "$ns" "$release"
   local rc=0
   _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- \
      vault kv put "$secret_path" "${KEYCLOAK_ADMIN_PASSWORD_KEY}=${password}" || rc=$?
   if (( rc != 0 )); then
      _err "[keycloak] Failed to seed admin password in Vault (exit code $rc)."
      return "$rc"
   fi

   _info "[keycloak] Admin password seeded at ${secret_path}"
}


function _keycloak_ensure_admin_secret() {
   if _kubectl --no-exit -n "$KEYCLOAK_NAMESPACE" get secret "$KEYCLOAK_ADMIN_SECRET_NAME" >/dev/null 2>&1; then
      return 0
   fi

   local password
   password=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#%^&*' </dev/urandom | head -c 24)

   cat <<EOF | _kubectl apply -f - >/dev/null
apiVersion: v1
kind: Secret
metadata:
  name: ${KEYCLOAK_ADMIN_SECRET_NAME}
  namespace: ${KEYCLOAK_NAMESPACE}
type: Opaque
stringData:
  ${KEYCLOAK_ADMIN_PASSWORD_KEY}: ${password}
EOF
}

function _keycloak_setup_vault_policies() {
   local ns="${VAULT_NS_DEFAULT:-vault}"
   local release="${VAULT_RELEASE_DEFAULT:-vault}"
   local pod="${release}-0"
   local policy_name="${KEYCLOAK_ESO_ROLE}"

   if _vault_policy_exists "$ns" "$release" "$policy_name"; then
      _info "[keycloak] Vault policy '$policy_name' exists, skipping"
      return 0
   fi

   _vault_login "$ns" "$release"

   cat <<POLICY | _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- \
     vault policy write "${KEYCLOAK_ESO_ROLE}" -
     path "secret/data/keycloak/*"      { capabilities = ["read"] }
     path "secret/metadata/keycloak"    { capabilities = ["list"] }
     path "secret/metadata/keycloak/*"  { capabilities = ["read","list"] }
     path "secret/data/ldap/*"          { capabilities = ["read"] }
     path "secret/metadata/ldap"        { capabilities = ["list"] }
     path "secret/metadata/ldap/*"      { capabilities = ["read","list"] }
POLICY

   _vault_exec_stream --no-exit --pod "$pod" "$ns" "$release" -- \
     vault write "auth/kubernetes/role/${policy_name}" \
       "bound_service_account_names=${KEYCLOAK_ESO_SERVICE_ACCOUNT}" \
       "bound_service_account_namespaces=${KEYCLOAK_NAMESPACE}" \
       "policies=${policy_name}" \
       ttl=1h

   _info "[keycloak] Vault policy and role configured"
}

function _keycloak_apply_realm_configmap() {
   local rendered
   rendered=$(mktemp -t keycloak-realm.XXXXXX.json)
   trap '$(_cleanup_trap_command "$rendered")' RETURN

   local bind_dn bind_pw
   bind_dn=$(_kubectl -n "$KEYCLOAK_NAMESPACE" get secret "$KEYCLOAK_LDAP_SECRET_NAME" -o jsonpath="{.data.${KEYCLOAK_LDAP_BINDDN_KEY}}" | base64 -d)
   bind_pw=$(_kubectl -n "$KEYCLOAK_NAMESPACE" get secret "$KEYCLOAK_LDAP_SECRET_NAME" -o jsonpath="{.data.${KEYCLOAK_LDAP_PASSWORD_KEY}}" | base64 -d)

   KEYCLOAK_LDAP_BIND_DN="$bind_dn" KEYCLOAK_LDAP_PASSWORD="$bind_pw" \
      envsubst '$KEYCLOAK_REALM_NAME $KEYCLOAK_REALM_DISPLAY_NAME $KEYCLOAK_LDAP_HOST $KEYCLOAK_LDAP_PORT $KEYCLOAK_LDAP_BASE_DN $KEYCLOAK_LDAP_USERS_DN $KEYCLOAK_LDAP_BIND_DN $KEYCLOAK_LDAP_PASSWORD' \
      < "$KEYCLOAK_CONFIG_DIR/realm-config.json.tmpl" > "$rendered"

   cat <<REALM | _kubectl apply -f - >/dev/null
apiVersion: v1
kind: ConfigMap
metadata:
  name: keycloak-realm-config
  namespace: $KEYCLOAK_NAMESPACE
data:
  realm-config.json: |
$(sed 's/^/    /' "$rendered")
REALM
}
