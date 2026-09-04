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
: "${KEYCLOAK_LDAP_HOST:=openldap.identity.svc.cluster.local}"
: "${KEYCLOAK_LDAP_PORT:=389}"
: "${KEYCLOAK_LDAP_BASE_DN:=dc=home,dc=org}"
: "${KEYCLOAK_LDAP_USERS_DN:=ou=users,dc=home,dc=org}"
: "${KEYCLOAK_REALM_NAME:=home}"
: "${KEYCLOAK_REALM_DISPLAY_NAME:=Home}"
: "${KEYCLOAK_MASTER_ADMIN_SECRET_NAME:=keycloak-secrets}"
: "${KEYCLOAK_SMOKE_REALM:=shopping-cart}"
: "${KEYCLOAK_SMOKE_CLIENT_ID:=k3dm-smoke}"
: "${KEYCLOAK_SMOKE_USERNAME:=k3dm-smoke}"
: "${KEYCLOAK_SMOKE_SECRET_NAME:=k3dm-smoke-user}"
# Realm the LDAP UserStorageProvider is cloned from (its config carries the
# proven field set; only bindCredential is repaired post-clone).
: "${KEYCLOAK_SMOKE_SRC_REALM:=home}"
# Master-admin secret actually deployed on this hub (Bitnami chart) — key 'password'.
: "${KEYCLOAK_SMOKE_ADMIN_SECRET_NAME:=keycloak-admin-secret}"
# frontendUrl pinned on the app realm so every locally-minted token carries the
# public issuer basket-service trusts (OAUTH2_ISSUER_URI base). Override to match
# the deployed app's issuer if it differs.
: "${KEYCLOAK_SMOKE_ISSUER_BASE_URL:=https://keycloak.3ai-talk.org}"
# LDAP admin bind for the READ_ONLY-federated smoke user (created as an LDAP entry).
: "${KEYCLOAK_LDAP_ADMIN_SECRET_NAME:=openldap-admin}"
: "${KEYCLOAK_LDAP_BIND_DN:=cn=ldap-admin,dc=home,dc=org}"
: "${KEYCLOAK_LDAP_POD:=openldap-0}"

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
         _err "[keycloak] Admin ExternalSecret not Ready; refusing to start Keycloak with an empty admin password"
         return 1
      fi
      local _admin_pw
      _admin_pw=$(_kubectl -n "$KEYCLOAK_NAMESPACE" get secret "$KEYCLOAK_ADMIN_SECRET_NAME" \
         -o jsonpath="{.data.${KEYCLOAK_ADMIN_PASSWORD_KEY}}" | base64 --decode)
      if [[ -z "${_admin_pw}" ]]; then
         _err "[keycloak] Secret '$KEYCLOAK_ADMIN_SECRET_NAME' has an empty '${KEYCLOAK_ADMIN_PASSWORD_KEY}'"
         return 1
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
   KEYCLOAK_CONFIG_CLI_ENABLED="$config_cli_enabled" \
   envsubst '$KEYCLOAK_ADMIN_USERNAME $KEYCLOAK_ADMIN_SECRET_NAME $KEYCLOAK_ADMIN_PASSWORD_KEY $KEYCLOAK_NAMESPACE $KEYCLOAK_SERVICE_PORT $KEYCLOAK_VIRTUALSERVICE_HOST $KEYCLOAK_CONFIG_CLI_ENABLED' \
      < "$KEYCLOAK_CONFIG_DIR/values.yaml.tmpl" > "$values_file"

   _info "[keycloak] Installing/Upgrading Helm release"
   local -a helm_version_args=()
   if [[ -n "${KEYCLOAK_HELM_CHART_VERSION:-}" ]]; then
      helm_version_args=(--version "$KEYCLOAK_HELM_CHART_VERSION")
   fi
   _helm upgrade --install -n "$KEYCLOAK_NAMESPACE" "$KEYCLOAK_HELM_RELEASE" "$KEYCLOAK_HELM_CHART_REF" \
      "${helm_version_args[@]}" --values "$values_file"

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
  ${KEYCLOAK_ADMIN_PASSWORD_KEY}: "${password}"
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

   cat <<POLICY | _vault_exec_stream --no-exit --stdin --pod "$pod" "$ns" "$release" -- \
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
   bind_dn=$(_kubectl -n "$KEYCLOAK_NAMESPACE" get secret "$KEYCLOAK_LDAP_SECRET_NAME" -o jsonpath="{.data.${KEYCLOAK_LDAP_BINDDN_KEY}}" | base64 --decode)
   bind_pw=$(_kubectl -n "$KEYCLOAK_NAMESPACE" get secret "$KEYCLOAK_LDAP_SECRET_NAME" -o jsonpath="{.data.${KEYCLOAK_LDAP_PASSWORD_KEY}}" | base64 --decode)

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

function _keycloak_reconcile_realm_client() {
   local base_url="${1:-}"
   local admin_token="${2:-}"
   local realm_name="${3:-}"
   local client_id="${4:-}"
   local realm_json_file="${5:-}"

   if [[ -z "$base_url" || -z "$admin_token" || -z "$realm_name" || -z "$client_id" || -z "$realm_json_file" ]]; then
      _err "[keycloak] usage: _keycloak_reconcile_realm_client <base_url> <admin_token> <realm_name> <client_id> <realm_json_file>"
      return 1
   fi

   if [[ ! -r "$realm_json_file" ]]; then
      _err "[keycloak] Realm JSON file not readable: $realm_json_file"
      return 1
   fi

   local client_payload
   client_payload=$(jq -c --arg clientId "$client_id" \
      '.clients[] | select(.clientId == $clientId)' "$realm_json_file" 2>/dev/null || true)
   if [[ -z "$client_payload" ]]; then
      _err "[keycloak] Client '$client_id' not found in realm JSON: $realm_json_file"
      return 1
   fi

   local client_uuid
   client_uuid=$(_curl -sf \
      -H "Authorization: Bearer ${admin_token}" \
      "${base_url}/admin/realms/${realm_name}/clients?clientId=${client_id}" \
      | jq -r '.[0].id // empty' 2>/dev/null || true)
   if [[ -z "$client_uuid" ]]; then
      _err "[keycloak] Client '$client_id' not found in Keycloak realm '$realm_name'"
      return 1
   fi

   client_payload=$(printf '%s' "$client_payload" | jq --arg id "$client_uuid" '.id = $id')

   _curl -sf \
      -X PUT \
      -H "Authorization: Bearer ${admin_token}" \
      -H "Content-Type: application/json" \
      --data-binary "$client_payload" \
      "${base_url}/admin/realms/${realm_name}/clients/${client_uuid}" >/dev/null

   _info "[keycloak] Reconciled client '$client_id' in realm '$realm_name'"
}

function _keycloak_remove_client_attribute() {
   local realm_name="${1:-}"
   local client_id="${2:-}"
   local attribute_name="${3:-}"
   local ns="${4:-$KEYCLOAK_NAMESPACE}"

   if [[ -z "$realm_name" || -z "$client_id" || -z "$attribute_name" ]]; then
      _err "[keycloak] usage: _keycloak_remove_client_attribute <realm_name> <client_id> <attribute_name> [namespace]"
      return 1
   fi

   local db_secret_name db_secret
   for db_secret_name in keycloak-secrets "$KEYCLOAK_ADMIN_SECRET_NAME"; do
      db_secret=$(_kubectl -n "$ns" get secret "$db_secret_name" -o jsonpath="{.data.KC_DB_PASSWORD}" 2>/dev/null | base64 --decode 2>/dev/null || true)
      if [[ -n "$db_secret" ]]; then
         break
      fi
   done
   if [[ -z "${db_secret:-}" ]]; then
      _warn "[keycloak] KC_DB_PASSWORD not available; skipping client attribute cleanup for '$client_id'"
      return 0
   fi

   local db_pod
   db_pod=$(_kubectl -n "$ns" get pod -l app.kubernetes.io/name=postgres-keycloak -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
   if [[ -z "$db_pod" ]]; then
      _warn "[keycloak] postgres-keycloak pod not found; skipping client attribute cleanup for '$client_id'"
      return 0
   fi

   local escaped_realm escaped_client escaped_attribute
   escaped_realm=${realm_name//\'/\'\'}
   escaped_client=${client_id//\'/\'\'}
   escaped_attribute=${attribute_name//\'/\'\'}

   _kubectl -n "$ns" exec -i "$db_pod" -- bash <<KEYCLOAK_PSQL >/dev/null
export PGPASSWORD="$db_secret"
psql -U keycloak -d keycloak -v ON_ERROR_STOP=1 -c "delete from client_attributes using client, realm where client_attributes.client_id = client.id and client.realm_id = realm.id and realm.name = '${escaped_realm}' and client.client_id = '${escaped_client}' and client_attributes.name = '${escaped_attribute}';"
KEYCLOAK_PSQL

   _info "[keycloak] Removed client attribute '$attribute_name' from '$client_id' in realm '$realm_name' if present"
}

function _keycloak_smoke_base_url() {
   if [[ -n "${KEYCLOAK_BASE_URL:-}" ]]; then
      printf '%s' "$KEYCLOAK_BASE_URL"
   elif [[ "${CLUSTER_PROVIDER:-}" == "k3s-hostinger" ]]; then
      printf '%s' "https://keycloak.3ai-talk.org"
   else
      printf '%s' "http://keycloak.shopping-cart.local"
   fi
}

function _keycloak_smoke_admin_token() {
   local base_url="$1" ns="$2" admin_secret="$3" wd="$4"
   local admin_user admin_pass
   admin_user=$(_kubectl --no-exit -n "$ns" get secret "$admin_secret" -o jsonpath='{.data.KEYCLOAK_ADMIN}' 2>/dev/null | base64 --decode 2>/dev/null || true)
   admin_pass=$(_kubectl --no-exit -n "$ns" get secret "$admin_secret" -o jsonpath='{.data.KEYCLOAK_ADMIN_PASSWORD}' 2>/dev/null | base64 --decode 2>/dev/null || true)
   if [[ -z "$admin_user" ]]; then
      admin_user="${KEYCLOAK_ADMIN_USERNAME:-admin}"
   fi
   if [[ -z "$admin_pass" ]]; then
      admin_pass=$(_kubectl --no-exit -n "$ns" get secret "$admin_secret" \
         -o jsonpath="{.data.${KEYCLOAK_ADMIN_PASSWORD_KEY:-password}}" 2>/dev/null | base64 --decode 2>/dev/null || true)
   fi
   if [[ -z "$admin_user" || -z "$admin_pass" ]]; then
      _warn "[keycloak] master admin creds not found in secret '$admin_secret'; skipping smoke seed"
      return 0
   fi
   printf '%s' "$admin_user" > "$wd/u"
   printf '%s' "$admin_pass" > "$wd/p"
   _curl -sf \
      --data-urlencode grant_type=password \
      --data-urlencode client_id=admin-cli \
      --data-urlencode "username@$wd/u" \
      --data-urlencode "password@$wd/p" \
      "${base_url}/realms/master/protocol/openid-connect/token" \
      | jq -r '.access_token // empty' 2>/dev/null || true
}

function _keycloak_smoke_ensure_client() {
   local base_url="$1" token="$2" realm="$3" client_id="$4"
   local client_uuid
   client_uuid=$(_curl -sf -H "Authorization: Bearer ${token}" \
      "${base_url}/admin/realms/${realm}/clients?clientId=${client_id}" \
      | jq -r '.[0].id // empty' 2>/dev/null || true)
   if [[ -n "$client_uuid" ]]; then
      return 0
   fi
   if ! _curl -sf -X POST \
         -H "Authorization: Bearer ${token}" \
         -H "Content-Type: application/json" \
         --data-binary "$(jq -n --arg cid "$client_id" '{clientId:$cid, enabled:true, protocol:"openid-connect", publicClient:true, directAccessGrantsEnabled:true, standardFlowEnabled:false, serviceAccountsEnabled:false}')" \
         "${base_url}/admin/realms/${realm}/clients" >/dev/null; then
      return 1
   fi
   _info "[keycloak] created smoke client '${client_id}' in realm '${realm}'"
   return 0
}

function _keycloak_smoke_ensure_user() {
   local base_url="$1" token="$2" realm="$3" username="$4"
   local user_uuid
   user_uuid=$(_curl -sf -H "Authorization: Bearer ${token}" \
      "${base_url}/admin/realms/${realm}/users?username=${username}&exact=true" \
      | jq -r '.[0].id // empty' 2>/dev/null || true)
   if [[ -z "$user_uuid" ]]; then
      if ! _curl -sf -X POST \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            --data-binary "$(jq -n --arg u "$username" '{username:$u, enabled:true, emailVerified:true, email:($u + "@k3dm.local"), firstName:$u, lastName:"smoke", requiredActions:[]}')" \
            "${base_url}/admin/realms/${realm}/users" >/dev/null; then
         return 1
      fi
      user_uuid=$(_curl -sf -H "Authorization: Bearer ${token}" \
         "${base_url}/admin/realms/${realm}/users?username=${username}&exact=true" \
         | jq -r '.[0].id // empty' 2>/dev/null || true)
   fi
   if [[ -n "$user_uuid" ]]; then
      if ! _curl -sf -X PUT \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            --data-binary "$(jq -n --arg u "$username" '{enabled:true, emailVerified:true, email:($u + "@k3dm.local"), firstName:$u, lastName:"smoke", requiredActions:[]}')" \
            "${base_url}/admin/realms/${realm}/users/${user_uuid}" >/dev/null; then
         return 1
      fi
   fi
   printf '%s' "$user_uuid"
}

function _keycloak_smoke_set_password() {
   local base_url="$1" token="$2" realm="$3" uuid="$4" password="$5" wd="$6"
   jq -n --arg p "$password" '{type:"password", value:$p, temporary:false}' > "$wd/reset.json"
   if ! _curl -sf -X PUT \
         -H "Authorization: Bearer ${token}" \
         -H "Content-Type: application/json" \
         --data-binary "@$wd/reset.json" \
         "${base_url}/admin/realms/${realm}/users/${uuid}/reset-password" >/dev/null; then
      return 1
   fi
   return 0
}

function _keycloak_smoke_write_secret() {
   local ns="$1" secret_name="$2" username="$3" password="$4" wd="$5"
   printf '%s' "$username" > "$wd/uname"
   printf '%s' "$password" > "$wd/pword"
   _kubectl -n "$ns" create secret generic "$secret_name" \
      --from-file=username="$wd/uname" \
      --from-file=password="$wd/pword" \
      --dry-run=client -o yaml | _kubectl apply -f - >/dev/null
}

function keycloak_seed_smoke_user() {
   if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
      cat <<'HELP'
Usage: keycloak_seed_smoke_user

Idempotently seed a dedicated smoke client + local user in the app realm so the
login smoke test (make status) can prove real realm-user auth without touching the
app-owned 'frontend' client. Warns and returns 0 if Keycloak or the app realm is
not reachable.
HELP
      return 0
   fi

   local realm="${KEYCLOAK_SMOKE_REALM:-shopping-cart}"
   local client_id="${KEYCLOAK_SMOKE_CLIENT_ID:-k3dm-smoke}"
   local username="${KEYCLOAK_SMOKE_USERNAME:-k3dm-smoke}"
   local secret_name="${KEYCLOAK_SMOKE_SECRET_NAME:-k3dm-smoke-user}"
   local ns="${KEYCLOAK_NAMESPACE:-identity}"
   local admin_secret="${KEYCLOAK_MASTER_ADMIN_SECRET_NAME:-keycloak-secrets}"

   local wd
   wd=$(mktemp -d -t kc-smoke.XXXXXX)
   trap 'rm -rf "$wd"' RETURN

   local base_url token
   base_url=$(_keycloak_smoke_base_url)
   token=$(_keycloak_smoke_admin_token "$base_url" "$ns" "$admin_secret" "$wd")
   if [[ -z "$token" ]]; then
      _warn "[keycloak] could not mint master admin token at ${base_url}; skipping smoke seed"
      return 0
   fi

   if ! _curl -sf -o /dev/null -H "Authorization: Bearer ${token}" \
        "${base_url}/admin/realms/${realm}"; then
      _warn "[keycloak] realm '${realm}' not present yet; skipping smoke seed"
      return 0
   fi

   local password
   password=$(_kubectl --no-exit -n "$ns" get secret "$secret_name" -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode 2>/dev/null || true)
   if [[ -z "$password" ]]; then
      password=$(openssl rand -hex 24)
   fi

   if ! _keycloak_smoke_ensure_client "$base_url" "$token" "$realm" "$client_id"; then
      _warn "[keycloak] failed to create smoke client '${client_id}'"
      return 0
   fi

   local user_uuid
   user_uuid=$(_keycloak_smoke_ensure_user "$base_url" "$token" "$realm" "$username")
   if [[ -z "$user_uuid" ]]; then
      _warn "[keycloak] smoke user '${username}' not resolvable after create; skipping"
      return 0
   fi

   if ! _keycloak_smoke_set_password "$base_url" "$token" "$realm" "$user_uuid" "$password" "$wd"; then
      _warn "[keycloak] failed to set smoke user password"
      return 0
   fi

   _keycloak_smoke_write_secret "$ns" "$secret_name" "$username" "$password" "$wd"
   _info "[keycloak] smoke user '${username}' seeded in realm '${realm}' (secret ${ns}/${secret_name})"
}

function _keycloak_smoke_ensure_realm() {
   local base_url="$1" token="$2" realm="$3" frontend_url="$4" wd="$5"
   if ! _curl -sf -o /dev/null -H "Authorization: Bearer ${token}" \
        "${base_url}/admin/realms/${realm}"; then
      if ! _curl -sf -X POST \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            --data-binary "$(jq -n --arg r "$realm" --arg fu "$frontend_url" \
               '{realm:$r, enabled:true, displayName:"Shopping Cart", sslRequired:"external", registrationAllowed:false, loginWithEmailAllowed:true, attributes:{frontendUrl:$fu}}')" \
            "${base_url}/admin/realms" >/dev/null; then
         return 1
      fi
      _info "[keycloak] created realm '${realm}'"
   fi
   local rep
   rep=$(_curl -sf -H "Authorization: Bearer ${token}" "${base_url}/admin/realms/${realm}" 2>/dev/null || true)
   [[ -z "$rep" ]] && return 1
   printf '%s' "$rep" | jq --arg fu "$frontend_url" \
      '.attributes = ((.attributes // {}) + {frontendUrl:$fu})' > "$wd/realm.json"
   _curl -sf -X PUT -H "Authorization: Bearer ${token}" -H "Content-Type: application/json" \
      --data-binary "@$wd/realm.json" "${base_url}/admin/realms/${realm}" >/dev/null || return 1
   return 0
}

function _keycloak_smoke_ensure_ldap_component() {
   local base_url="$1" token="$2" realm="$3" src_realm="$4" bind_pw="$5" wd="$6"
   local comp_id
   comp_id=$(_curl -sf -H "Authorization: Bearer ${token}" \
      "${base_url}/admin/realms/${realm}/components?type=org.keycloak.storage.UserStorageProvider" \
      | jq -r '.[0].id // empty' 2>/dev/null || true)
   if [[ -z "$comp_id" ]]; then
      local src
      src=$(_curl -sf -H "Authorization: Bearer ${token}" \
         "${base_url}/admin/realms/${src_realm}/components?type=org.keycloak.storage.UserStorageProvider" \
         | jq -r '.[0] // empty' 2>/dev/null || true)
      if [[ -z "$src" || "$src" == "null" ]]; then
         return 2
      fi
      printf '%s' "$src" | jq 'del(.id) | del(.parentId)' > "$wd/ldap.json"
      _curl -sf -X POST -H "Authorization: Bearer ${token}" -H "Content-Type: application/json" \
         --data-binary "@$wd/ldap.json" \
         "${base_url}/admin/realms/${realm}/components" >/dev/null || return 1
      comp_id=$(_curl -sf -H "Authorization: Bearer ${token}" \
         "${base_url}/admin/realms/${realm}/components?type=org.keycloak.storage.UserStorageProvider" \
         | jq -r '.[0].id // empty' 2>/dev/null || true)
      _info "[keycloak] cloned LDAP provider into realm '${realm}'"
   fi
   [[ -z "$comp_id" ]] && return 1
   # The clone copies the masked bindCredential ('**********') — replace it with
   # the real bind password or every federated-user mint fails LDAP error 49.
   local comp
   comp=$(_curl -sf -H "Authorization: Bearer ${token}" \
      "${base_url}/admin/realms/${realm}/components/${comp_id}" 2>/dev/null || true)
   [[ -z "$comp" ]] && return 1
   printf '%s' "$comp" | jq --arg pw "$bind_pw" '.config.bindCredential=[$pw]' > "$wd/ldapfix.json"
   _curl -sf -X PUT -H "Authorization: Bearer ${token}" -H "Content-Type: application/json" \
      --data-binary "@$wd/ldapfix.json" \
      "${base_url}/admin/realms/${realm}/components/${comp_id}" >/dev/null || return 1
   return 0
}

function _keycloak_smoke_ensure_ldap_user() {
   local ns="$1" pod="$2" ldap_url="$3" bind_dn="$4" bind_pw="$5"
   local user_dn="$6" username="$7" user_pw="$8"
   # Stage the admin bind password inside the pod at 0600 — never on argv.
   if ! printf '%s' "$bind_pw" | _kubectl --no-exit -n "$ns" exec -i "$pod" -- \
        sh -c 'umask 077; cat > /tmp/.kcbind' >/dev/null 2>&1; then
      return 1
   fi
   local rc=0
   if ! _kubectl --no-exit -n "$ns" exec "$pod" -- \
        ldapsearch -x -LLL -D "$bind_dn" -y /tmp/.kcbind -H "$ldap_url" -b "$user_dn" dn >/dev/null 2>&1; then
      if ! printf 'dn: %s\nobjectClass: inetOrgPerson\ncn: %s\nsn: smoke\nuid: %s\nmail: %s@k3dm.local\nuserPassword: %s\n' \
            "$user_dn" "$username" "$username" "$username" "$user_pw" \
            | _kubectl --no-exit -n "$ns" exec -i "$pod" -- \
               ldapadd -x -D "$bind_dn" -y /tmp/.kcbind -H "$ldap_url" >/dev/null 2>&1; then
         rc=1
      fi
   fi
   # Always assert the password so the written Secret is guaranteed to authenticate.
   if [[ $rc -eq 0 ]]; then
      if ! printf 'dn: %s\nchangetype: modify\nreplace: userPassword\nuserPassword: %s\n' \
            "$user_dn" "$user_pw" \
            | _kubectl --no-exit -n "$ns" exec -i "$pod" -- \
               ldapmodify -x -D "$bind_dn" -y /tmp/.kcbind -H "$ldap_url" >/dev/null 2>&1; then
         rc=1
      fi
   fi
   _kubectl --no-exit -n "$ns" exec "$pod" -- rm -f /tmp/.kcbind >/dev/null 2>&1 || true
   return $rc
}

function keycloak_provision_shopping_cart_realm() {
   if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
      cat <<'HELP'
Usage: keycloak_provision_shopping_cart_realm

Idempotently provision the LDAP-backed 'shopping-cart' realm on the hub Keycloak so
the make-status login smoke test proves a real end-to-end 200 through /api/cart:

  - creates the realm and pins attributes.frontendUrl to the public issuer
    (KEYCLOAK_SMOKE_ISSUER_BASE_URL) so every locally-minted token carries the
    'iss' basket-service trusts — no Cloudflare round-trip;
  - clones the LDAP UserStorageProvider from KEYCLOAK_SMOKE_SRC_REALM and repairs
    the masked bindCredential with the real LDAP admin password;
  - creates the public direct-grant client (KEYCLOAK_SMOKE_CLIENT_ID);
  - adds the smoke user as an LDAP entry (READ_ONLY federation refuses local users)
    with a generated password (reused from the existing Secret if present);
  - writes Secret <namespace>/<KEYCLOAK_SMOKE_SECRET_NAME> (keys username, password,
    realm, client) for the webhook smoke harness.

The admin API is reached via _keycloak_smoke_base_url; set KEYCLOAK_BASE_URL
(e.g. http://localhost:8880 with the keycloak port-forward up) for a reliable path.
Warns and returns 0 if a prerequisite is missing — never a hard failure.
HELP
      return 0
   fi

   local realm="${KEYCLOAK_SMOKE_REALM:-shopping-cart}"
   local src_realm="${KEYCLOAK_SMOKE_SRC_REALM:-home}"
   local client_id="${KEYCLOAK_SMOKE_CLIENT_ID:-k3dm-smoke}"
   local username="${KEYCLOAK_SMOKE_USERNAME:-k3dm-smoke}"
   local secret_name="${KEYCLOAK_SMOKE_SECRET_NAME:-k3dm-smoke-user}"
   local ns="${KEYCLOAK_NAMESPACE:-identity}"
   local admin_secret="${KEYCLOAK_SMOKE_ADMIN_SECRET_NAME:-keycloak-admin-secret}"
   local frontend_url="${KEYCLOAK_SMOKE_ISSUER_BASE_URL:-https://keycloak.3ai-talk.org}"

   local ldap_secret="${KEYCLOAK_LDAP_ADMIN_SECRET_NAME:-openldap-admin}"
   local ldap_pw_key="${KEYCLOAK_LDAP_PASSWORD_KEY:-LDAP_ADMIN_PASSWORD}"
   local ldap_bind_dn="${KEYCLOAK_LDAP_BIND_DN:-cn=ldap-admin,dc=home,dc=org}"
   local ldap_pod="${KEYCLOAK_LDAP_POD:-openldap-0}"
   local ldap_url="ldap://${KEYCLOAK_LDAP_HOST:-openldap.identity.svc.cluster.local}:${KEYCLOAK_LDAP_PORT:-389}"
   local user_dn="cn=${username},${KEYCLOAK_LDAP_USERS_DN:-ou=users,dc=home,dc=org}"

   local wd
   wd=$(mktemp -d -t kc-provision.XXXXXX)
   trap 'rm -rf "$wd"' RETURN

   local base_url token
   base_url=$(_keycloak_smoke_base_url)
   token=$(_keycloak_smoke_admin_token "$base_url" "$ns" "$admin_secret" "$wd")
   if [[ -z "$token" ]]; then
      _warn "[keycloak] could not mint master admin token at ${base_url}; skipping realm provision"
      return 0
   fi

   local ldap_pw
   ldap_pw=$(_kubectl --no-exit -n "$ns" get secret "$ldap_secret" \
      -o jsonpath="{.data.${ldap_pw_key}}" 2>/dev/null | base64 --decode 2>/dev/null || true)
   if [[ -z "$ldap_pw" ]]; then
      _warn "[keycloak] LDAP admin password not found in secret '${ldap_secret}'; skipping realm provision"
      return 0
   fi

   if ! _keycloak_smoke_ensure_realm "$base_url" "$token" "$realm" "$frontend_url" "$wd"; then
      _warn "[keycloak] failed to provision realm '${realm}'"
      return 0
   fi

   _keycloak_smoke_ensure_ldap_component "$base_url" "$token" "$realm" "$src_realm" "$ldap_pw" "$wd"
   case $? in
      0) : ;;
      2) _warn "[keycloak] no LDAP provider in source realm '${src_realm}'; skipping realm provision"; return 0 ;;
      *) _warn "[keycloak] failed to provision LDAP provider in realm '${realm}'"; return 0 ;;
   esac

   if ! _keycloak_smoke_ensure_client "$base_url" "$token" "$realm" "$client_id"; then
      _warn "[keycloak] failed to create smoke client '${client_id}'"
      return 0
   fi

   local password
   password=$(_kubectl --no-exit -n "$ns" get secret "$secret_name" \
      -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode 2>/dev/null || true)
   if [[ -z "$password" ]]; then
      password=$(openssl rand -hex 24)
   fi

   if ! _keycloak_smoke_ensure_ldap_user "$ns" "$ldap_pod" "$ldap_url" "$ldap_bind_dn" "$ldap_pw" \
        "$user_dn" "$username" "$password"; then
      _warn "[keycloak] failed to seed LDAP smoke user '${user_dn}'"
      return 0
   fi

   printf '%s' "$username" > "$wd/uname"
   printf '%s' "$password" > "$wd/pword"
   printf '%s' "$realm" > "$wd/realmkey"
   printf '%s' "$client_id" > "$wd/clientkey"
   _kubectl -n "$ns" create secret generic "$secret_name" \
      --from-file=username="$wd/uname" \
      --from-file=password="$wd/pword" \
      --from-file=realm="$wd/realmkey" \
      --from-file=client="$wd/clientkey" \
      --dry-run=client -o yaml | _kubectl apply -f - >/dev/null
   _info "[keycloak] provisioned realm '${realm}' (frontendUrl=${frontend_url}); smoke user '${username}' seeded (secret ${ns}/${secret_name})"
}

function test_keycloak() {
   local ns="${KEYCLOAK_NAMESPACE:-identity}"
   local service_port="${KEYCLOAK_SERVICE_PORT:-8080}"

   _info "[keycloak] Running smoke test in namespace '$ns'"

   if ! _kubectl --no-exit -n "$ns" get statefulset keycloak >/dev/null 2>&1; then
      _err "[keycloak] StatefulSet 'keycloak' not found in namespace '$ns'"
   fi

   if ! _kubectl -n "$ns" wait --for=condition=Ready --timeout=300s pod/keycloak-0 >/dev/null 2>&1; then
      _err "[keycloak] Pod keycloak-0 is not Ready"
   fi

   local admin_secret
   admin_secret=$(_kubectl --no-exit -n "$ns" get secret "$KEYCLOAK_ADMIN_SECRET_NAME" -o jsonpath="{.data.${KEYCLOAK_ADMIN_PASSWORD_KEY}}" 2>/dev/null || true)
   if [[ -z "$admin_secret" ]]; then
      _err "[keycloak] Secret '$KEYCLOAK_ADMIN_SECRET_NAME' missing key '${KEYCLOAK_ADMIN_PASSWORD_KEY}'"
   fi

   local es
   for es in "$KEYCLOAK_ADMIN_SECRET_NAME" "$KEYCLOAK_LDAP_SECRET_NAME"; do
      if ! _kubectl --no-exit -n "$ns" get externalsecret "$es" >/dev/null 2>&1; then
         _warn "[keycloak] ExternalSecret '$es' not found in namespace '$ns' — skipping"
         continue
      fi
      if ! _kubectl -n "$ns" wait --for=condition=Ready --timeout=60s externalsecret/"$es" 2>/dev/null; then
         _err "[keycloak] ExternalSecret '$es' not Ready"
      fi
   done

   local marker="KEYCLOAK_HTTP_STATUS"
   local curl_cmd="curl -s -o /dev/null -w '${marker}:%{http_code}' http://keycloak.${ns}.svc.cluster.local:${service_port}/realms/master"
   local output
   output=$(_kubectl --no-exit -n "$ns" run "keycloak-http-$RANDOM$RANDOM" --rm -i --restart=Never \
      --image=curlimages/curl:8.10.1 --command -- sh -c "$curl_cmd" 2>&1 || true)
   output=${output//$'\r'/}
   local status_line
   status_line=$(printf '%s\n' "$output" | grep -Eo "${marker}:[0-9]{3}" | tail -n1)
   local http_code="${status_line##*:}"
   if [[ -z "$status_line" || "$http_code" != "200" ]]; then
      _err "[keycloak] HTTP check failed; response code: ${http_code:-unknown}"
   fi

   _info "[keycloak] Smoke test passed"
}
