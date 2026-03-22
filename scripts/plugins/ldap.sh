# shellcheck disable=SC1090,SC2034,SC2016,SC2154,SC2153

LDAP_CONFIG_DIR="$SCRIPT_DIR/etc/ldap"
LDAP_VARS_FILE="$LDAP_CONFIG_DIR/vars.sh"

if [[ ! -r "$LDAP_VARS_FILE" ]]; then
   _err "[ldap] vars file missing: $LDAP_VARS_FILE"
else
   # shellcheck disable=SC1090
   source "$LDAP_VARS_FILE"
fi

# Source Vault plugin if not already loaded
if ! declare -f deploy_vault >/dev/null 2>&1; then
   VAULT_PLUGIN="$PLUGINS_DIR/vault.sh"
   if [[ ! -r "$VAULT_PLUGIN" ]]; then
      _err "[ldap] missing required plugin: $VAULT_PLUGIN"
   fi
   # shellcheck disable=SC1090
   source "$VAULT_PLUGIN"
fi

VAULT_VARS_FILE="$SCRIPT_DIR/etc/vault/vars.sh"
if [[ -r "$VAULT_VARS_FILE" ]]; then
   # shellcheck disable=SC1090
   source "$VAULT_VARS_FILE"
fi

function _enable_vault_secrets_engine() {
   local ns="${1:-$VAULT_NS_DEFAULT}"
   local release="${2:-$VAULT_RELEASE_DEFAULT}"
   local mount="${LDAP_VAULT_PATH:-ldap-ops}"

   _vault_exec "$ns" "vault secrets enable -path=${mount} ldap || true" "$release"
}

function _enable_vault_ldap_connection() {
   local ns="${1:-$VAULT_NS_DEFAULT}"
   local release="${2:-$VAULT_RELEASE_DEFAULT}"
   local mount="${LDAP_VAULT_PATH:-ldap-ops}"
   local -a args=(vault write "${mount}/config" "url=${LDAP_URL}" "binddn=${LDAP_BINDDN}")

   if [[ -n "${LDAP_BINDPASS:-}" ]]; then
      args+=("bindpass=${LDAP_BINDPASS}")
   fi
   if [[ -n "${LDAP_USERDN:-}" ]]; then
      args+=("userdn=${LDAP_USERDN}")
   fi
   if [[ -n "${LDAP_GROUPDN:-}" ]]; then
      args+=("groupdn=${LDAP_GROUPDN}")
   fi

   local cmd=""
   printf -v cmd '%q ' "${args[@]}"
   cmd=${cmd% }

   _vault_exec "$ns" "$cmd" "$release"
}

function _create_ldap_admin_role() {
   local ns="${1:-$VAULT_NS_DEFAULT}"
   local release="${2:-$VAULT_RELEASE_DEFAULT}"
   local mount="${LDAP_VAULT_PATH:-ldap-ops}"
   local role="${LDAP_APP_ROLE:-ldap-reader}"
   local pod="${release}-0"

   if _vault_exec --no-exit "$ns" "vault read ${mount}/roles/${role}" "$release" >/dev/null 2>&1; then
      _info "[ldap] ${role} role already exists; skipping"
      return 0
   fi

   cat <<EOF | _kubectl -n "$ns" exec -i "$pod" -- sh -
set -eu
vault write ${mount}/roles/${role} \
  lease=1h \
  creation_ldif=-<<'CREATION' \
  revocation_ldif=-<<'REVOCATION'
CREATION
dn: uid={{username}},${LDAP_USERDN}
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: person
sn: svc
cn: {{username}}
uid: {{username}}
userPassword: {{password}}
CREATION
REVOCATION
dn: uid={{username}},${LDAP_USERDN}
changetype: delete
REVOCATION
EOF
}

function _create_vault_ldap_admin_policy() {
   return 0
}

function _ldap_render_template() {
   local template="${1:?template path required}"
   local prefix="${2:-ldap}"

   if [[ ! -r "$template" ]]; then
      _err "[ldap] template not found: $template"
      return 1
   fi

   local rendered
   rendered=$(mktemp -t "${prefix}.XXXXXX.yaml") || return 1

   if ! envsubst < "$template" > "$rendered"; then
      rm -f "$rendered"
      return 1
   fi

   printf '%s\n' "$rendered"
}

function _ldap_ensure_namespace() {
   local ns="${1:-$LDAP_NAMESPACE}"

   if _kubectl --no-exit get namespace "$ns" >/dev/null 2>&1; then
      _info "[ldap] namespace ${ns} already exists, skipping"
      return 0
   fi

   _kubectl create namespace "$ns"
}

function _ldap_detect_eso_api_version() {
   local default_version="${LDAP_ESO_API_VERSION:-external-secrets.io/v1}"
   local group="external-secrets.io"
   local crd="secretstores.${group}"
   local served_versions=""
   local versions=""

   served_versions=$(_kubectl --no-exit get crd "$crd" -o jsonpath='{range .spec.versions[?(@.served==true)]}{.name}{" "}{end}' 2>/dev/null || true)
   if [[ -n "$served_versions" ]]; then
      if [[ "$served_versions" =~ (^|[[:space:]])v1($|[[:space:]]) ]]; then
         printf '%s\n' "${group}/v1"
         return 0
      fi
      if [[ "$served_versions" =~ (^|[[:space:]])v1beta1($|[[:space:]]) ]]; then
         printf '%s\n' "${group}/v1beta1"
         return 0
      fi
      if [[ "$served_versions" =~ (^|[[:space:]])v1alpha1($|[[:space:]]) ]]; then
         printf '%s\n' "${group}/v1alpha1"
         return 0
      fi
   fi

   versions=$(_kubectl --no-exit get crd "$crd" -o jsonpath='{.spec.versions[*].name}' 2>/dev/null || true)
   if [[ -n "$versions" ]]; then
      if [[ "$versions" =~ (^|[[:space:]])v1($|[[:space:]]) ]]; then
         printf '%s\n' "${group}/v1"
         return 0
      fi
      if [[ "$versions" =~ (^|[[:space:]])v1beta1($|[[:space:]]) ]]; then
         printf '%s\n' "${group}/v1beta1"
         return 0
      fi
      if [[ "$versions" =~ (^|[[:space:]])v1alpha1($|[[:space:]]) ]]; then
         printf '%s\n' "${group}/v1alpha1"
         return 0
      fi
   fi

   printf '%s\n' "$default_version"
}

function _ldap_apply_eso_resources() {
   local ns="${1:-$LDAP_NAMESPACE}"
   local tmpl="$LDAP_CONFIG_DIR/eso.yaml"
   local rendered
   local api_version
   local default_version="${LDAP_ESO_API_VERSION:-external-secrets.io/v1}"
   local ldif_block=""

   api_version=$(_ldap_detect_eso_api_version) || api_version="$default_version"
   _info "[ldap] using ESO API version ${api_version}"
   export LDAP_ESO_API_VERSION="$api_version"

   if [[ "${LDAP_LDIF_ENABLED:-false}" == "true" && -n "${LDAP_LDIF_VAULT_PATH:-}" ]]; then
      local ldif_name="${LDAP_LDIF_SECRET_NAME}"
      local ldif_refresh="${LDAP_LDIF_REFRESH_INTERVAL}"
      local ldif_secret_key="${LDAP_LDIF_SECRET_KEY}"
      local ldif_vault_path="${LDAP_LDIF_VAULT_PATH}"
      local ldif_content_key="${LDAP_LDIF_CONTENT_KEY}"
      local ldif_remote_property="${LDAP_LDIF_REMOTE_PROPERTY:-content}"
      local ldif_namespace="${LDAP_NAMESPACE}"
      local ldif_store="${LDAP_ESO_SECRETSTORE}"

      ldif_block=$(cat <<EOF
---
apiVersion: ${api_version}
kind: ExternalSecret
metadata:
  name: ${ldif_name}
  namespace: ${ldif_namespace}
spec:
  refreshInterval: ${ldif_refresh}
  secretStoreRef:
    name: ${ldif_store}
    kind: SecretStore
  target:
    name: ${ldif_name}
    creationPolicy: Owner
    template:
      type: Opaque
  data:
    - secretKey: ${ldif_secret_key}
      remoteRef:
        key: ${ldif_vault_path}
        property: ${ldif_remote_property}
EOF
)
   else
      ldif_block=""
   fi
   export LDAP_LDIF_EXTERNALSECRET_YAML="$ldif_block"

   rendered=$(_ldap_render_template "$tmpl" "ldap-eso") || return 1
   local apply_rc=0
   if ! _kubectl apply -f "$rendered"; then
      apply_rc=$?
   fi
   _cleanup_on_success "$rendered"
   return "$apply_rc"
}

# _ldap_resolve_chart_ref ...
function _ldap_resolve_chart_ref() {
   local helm_chart_ref_default="$1" helm_repo_name="$2" helm_repo_url="$3"
   local version="$4" chart_archive_candidate="$5"

   local chart_archive=""
   if [[ -n "$chart_archive_candidate" && -f "$chart_archive_candidate" ]]; then
      local archive_dir archive_name
      archive_dir="$(cd "$(dirname "$chart_archive_candidate")" >/dev/null 2>&1 && pwd)"
      archive_name="$(basename "$chart_archive_candidate")"
      chart_archive="${archive_dir}/${archive_name}"
   fi

   _LDAP_CHART_REF="${LDAP_HELM_CHART_REF:-$helm_chart_ref_default}"
   if [[ -n "$chart_archive" ]]; then
      _LDAP_CHART_REF="$chart_archive"
      _info "[ldap] using local Helm chart archive ${_LDAP_CHART_REF}"
   fi

   _LDAP_CHART_SKIP_REPO_OPS=0
   _LDAP_CHART_IS_OCI=0
   case "$_LDAP_CHART_REF" in
      /*|./*|../*|file://*) _LDAP_CHART_SKIP_REPO_OPS=1 ;;
      oci://*) _LDAP_CHART_SKIP_REPO_OPS=1; _LDAP_CHART_IS_OCI=1 ;;
   esac
   case "$helm_repo_url" in
      ""|/*|./*|../*|file://*) _LDAP_CHART_SKIP_REPO_OPS=1 ;;
   esac
}

function _ldap_ensure_helm_chart_available() {
   local helm_chart_ref="$1" version="$2" helm_repo_name="$3"
   local skip_repo_ops="$4" is_oci_ref="$5"

   if (( is_oci_ref )) && [[ -z "$version" ]]; then
      _err "[ldap] OCI charts require LDAP_HELM_CHART_VERSION. Set it to a published OpenLDAP chart version or point LDAP_HELM_CHART_ARCHIVE/LDAP_HELM_CHART_REF at a packaged chart."
      return 1
   fi

   local -a chart_probe=(show chart "$helm_chart_ref")
   if [[ -n "$version" ]]; then
      chart_probe+=("--version" "$version")
   fi

   if ! _helm --no-exit "${chart_probe[@]}" >/dev/null 2>&1; then
      if (( ! skip_repo_ops )); then
         _warn "[ldap] Helm repo ${helm_repo_name} missing chart ${helm_chart_ref}; retrying index update."
         if ! _helm --no-exit repo update "$helm_repo_name"; then
            _err "[ldap] unable to refresh Helm repo ${helm_repo_name}; run 'helm repo update ${helm_repo_name}' or set LDAP_HELM_CHART_ARCHIVE/LDAP_HELM_CHART_REF to a local chart path."
            return 1
         fi
         if ! _helm --no-exit "${chart_probe[@]}" >/dev/null 2>&1; then
            _err "[ldap] chart ${helm_chart_ref} still unavailable. Run 'helm repo update ${helm_repo_name}' manually or point LDAP_HELM_CHART_ARCHIVE/LDAP_HELM_CHART_REF to a local package."
            return 1
         fi
      else
         if (( is_oci_ref )); then
            local version_hint="${version:-<required>}"
            _err "[ldap] OCI chart ${helm_chart_ref} is unreachable. Pull it with 'helm pull ${helm_chart_ref} --version ${version_hint}' and reference the cached file, or ensure registry access is available."
         else
            _err "[ldap] chart reference ${helm_chart_ref} not found; set LDAP_HELM_CHART_ARCHIVE/LDAP_HELM_CHART_REF to a valid chart location."
         fi
         return 1
      fi
   fi
}

# _ldap_generate_or_load_admin_creds
# Reads existing admin/config passwords from Vault or generates new ones.
# Sets globals: _LDAP_ADMIN_CRED_USERNAME _LDAP_ADMIN_CRED_ADMIN_PASS _LDAP_ADMIN_CRED_CONFIG_PASS
# Args: $1=vault_ns $2=vault_release $3=full_path $4=username_key $5=password_key $6=config_key $7=username
function _ldap_generate_or_load_admin_creds() {
   local vault_ns="$1" vault_release="$2" full_path="$3"
   local username_key="$4" password_key="$5" config_key="$6" username="$7"

   local existing_json=""
   existing_json=$(_vault_exec --no-exit "$vault_ns" "vault kv get -format=json ${full_path}" "$vault_release" 2>&1 || true)
   existing_json=${existing_json//$'\r'/}
   if [[ "$existing_json" == *"Error making API request"* ]] || [[ "$existing_json" != "{"* ]]; then
      existing_json=""
   fi

   local existing_username="" admin_password="" config_password=""
   if [[ -n "$existing_json" ]]; then
      existing_username=$(printf '%s' "$existing_json" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("data",{}).get("data",{}).get(sys.argv[1],""))' "$username_key" 2>/dev/null || true)
      admin_password=$(printf '%s' "$existing_json" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("data",{}).get("data",{}).get(sys.argv[1],""))' "$password_key" 2>/dev/null || true)
      config_password=$(printf '%s' "$existing_json" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("data",{}).get("data",{}).get(sys.argv[1],""))' "$config_key" 2>/dev/null || true)
   fi

   _LDAP_ADMIN_CRED_USERNAME="${existing_username:-$username}"

   if [[ -z "$admin_password" ]]; then
      admin_password=$(_no_trace bash -c 'openssl rand -base64 24 | tr -d "\n"')
      if [[ -z "$admin_password" ]]; then
         _err "[ldap] failed to generate admin password"
      fi
   fi
   if [[ -z "$config_password" ]]; then
      config_password=$(_no_trace bash -c 'openssl rand -base64 24 | tr -d "\n"')
      if [[ -z "$config_password" ]]; then
         _err "[ldap] failed to generate config password"
      fi
   fi

   _LDAP_ADMIN_CRED_ADMIN_PASS="$admin_password"
   _LDAP_ADMIN_CRED_CONFIG_PASS="$config_password"
}

function _ldap_seed_admin_secret() {
   local vault_ns="${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}"
   local vault_release="${VAULT_RELEASE:-${VAULT_RELEASE_DEFAULT:-vault}}"
   local mount="${LDAP_VAULT_KV_MOUNT:-secret}"
   local vault_path="${LDAP_ADMIN_VAULT_PATH:-ldap/openldap-admin}"
   local username_key="${LDAP_ADMIN_USERNAME_KEY:-LDAP_ADMIN_USERNAME}"
   local password_key="${LDAP_ADMIN_PASSWORD_KEY:-LDAP_ADMIN_PASSWORD}"
   local config_key="${LDAP_CONFIG_PASSWORD_KEY:-LDAP_CONFIG_PASSWORD}"
   local username="${LDAP_ADMIN_USERNAME:-ldap-admin}"
   local base_dn="${LDAP_BASE_DN:-dc=${LDAP_DC_PRIMARY:-home},dc=${LDAP_DC_SECONDARY:-org}}"

   local full_path="${mount}/${vault_path}"

   if ! _vault_exec --no-exit "$vault_ns" "vault status >/dev/null 2>&1" "$vault_release"; then
      _err "[ldap] Vault instance ${vault_ns}/${vault_release} unavailable or sealed; unseal before deploy"
   fi
   _ldap_generate_or_load_admin_creds \
      "$vault_ns" "$vault_release" "$full_path" \
      "$username_key" "$password_key" "$config_key" "$username"
   local username="${_LDAP_ADMIN_CRED_USERNAME}"
   local admin_password="${_LDAP_ADMIN_CRED_ADMIN_PASS}"
   local config_password="${_LDAP_ADMIN_CRED_CONFIG_PASS}"

   local domain="${LDAP_DOMAIN}"
   local root_dn="${LDAP_ROOT}"
   local bind_dn="${LDAP_BINDDN}"
   local base_dn_key="${LDAP_BASE_DN_KEY:-LDAP_BASE_DN}"
   local bind_dn_key="${LDAP_BIND_DN_KEY:-LDAP_BINDDN}"
   local domain_key="${LDAP_DOMAIN_KEY:-LDAP_DOMAIN}"
   local root_key="${LDAP_ROOT_KEY:-LDAP_ROOT}"
   local org_key="${LDAP_ORG_NAME_KEY:-LDAP_ORG_NAME}"

   local payload=""
   payload=$(USERNAME_KEY="$username_key" USERNAME="$username" \
      ADMIN_PASS_KEY="$password_key" ADMIN_PASS="$admin_password" \
      CONFIG_PASS_KEY="$config_key" CONFIG_PASS="$config_password" \
      BASE_DN_KEY="$base_dn_key" BASE_DN="$base_dn" \
      BIND_DN_KEY="$bind_dn_key" BIND_DN="$bind_dn" \
      DOMAIN_KEY="$domain_key" LDAP_DOMAIN_VALUE="$domain" \
      ROOT_KEY="$root_key" ROOT_DN="$root_dn" \
      ORG_KEY="$org_key" ORG_NAME="$LDAP_ORG_NAME" \
      python3 <<'PY'
import json, os
data = {
    os.environ['USERNAME_KEY']: os.environ['USERNAME'],
    os.environ['ADMIN_PASS_KEY']: os.environ['ADMIN_PASS'],
   os.environ['CONFIG_PASS_KEY']: os.environ['CONFIG_PASS'],
   os.environ['BASE_DN_KEY']: os.environ['BASE_DN'],
   os.environ['BIND_DN_KEY']: os.environ['BIND_DN'],
   os.environ['DOMAIN_KEY']: os.environ['LDAP_DOMAIN_VALUE'],
   os.environ['ROOT_KEY']: os.environ['ROOT_DN'],
    os.environ['ORG_KEY']: os.environ['ORG_NAME'],
}
print(json.dumps(data))
PY
)

   if [[ -z "$payload" ]]; then
      _err "[ldap] failed to serialize Vault admin payload"
   fi

   export LDAP_VAULT_ADMIN_PASSWORD="$admin_password"
   export LDAP_VAULT_CONFIG_PASSWORD="$config_password"
   export LDAP_VAULT_ADMIN_USERNAME="$username"
   export LDAP_VAULT_BASE_DN="$base_dn"
   export LDAP_VAULT_DOMAIN="$domain"
   export LDAP_VAULT_ROOT_DN="$root_dn"
   export LDAP_VAULT_ORG_NAME="$org_name_value"

   # Use secret backend abstraction instead of direct vault commands to avoid UI endpoint issues
   if declare -f secret_backend_put >/dev/null 2>&1; then
      export VAULT_SECRET_BACKEND_NS="$vault_ns"
      export VAULT_SECRET_BACKEND_RELEASE="$vault_release"
      export VAULT_SECRET_BACKEND_MOUNT="${mount}"

      if secret_backend_put "$vault_path" \
         "${username_key}=${username}" \
         "${password_key}=${admin_password}" \
         "${config_key}=${config_password}" \
         "${base_dn_key}=${base_dn}" \
         "${bind_dn_key}=${bind_dn}" \
         "${domain_key}=${domain}" \
         "${root_key}=${root_dn}" \
         "${org_key}=${LDAP_ORG_NAME}"; then
         _info "[ldap] seeded Vault secret ${full_path}"
         return 0
      fi
   else
      # Fallback to direct vault command
      local script
      printf -v script "cat <<'EOF' | vault kv put %s -\n%s\nEOF" \
         "$full_path" "$payload"

      if _vault_exec --no-exit "$vault_ns" "$script" "$vault_release"; then
         _info "[ldap] seeded Vault secret ${full_path}"
         return 0
      fi
   fi

   _err "[ldap] unable to seed Vault admin secret ${full_path}"
}

function _ldap_build_ldif_content() {
   local base_dn="$1" org_name="$2" dc_primary="$3"
   local group_ou="$4" service_ou="$5"
   local enable_jenkins="$6" jenkins_password="$7" jenkins_user_dn="$8"
   local group_ou_value="${group_ou#*=}"
   local service_ou_value="${service_ou#*=}"

   if [[ -n "${LDAP_LDIF_FILE:-}" && -f "${LDAP_LDIF_FILE}" ]]; then
      _info "[ldap] loading custom LDIF from file: ${LDAP_LDIF_FILE}"
      _LDAP_LDIF_CONTENT=$(cat "${LDAP_LDIF_FILE}")
      if [[ -z "$_LDAP_LDIF_CONTENT" ]]; then
         _err "[ldap] custom LDIF file is empty: ${LDAP_LDIF_FILE}"
         return 1
      fi
      return 0
   fi

   _LDAP_LDIF_CONTENT=$(cat <<EOF
dn: ${base_dn}
objectClass: top
objectClass: dcObject
objectClass: organization
o: ${org_name}
dc: ${dc_primary}

dn: ${group_ou},${base_dn}
objectClass: top
objectClass: organizationalUnit
ou: ${group_ou_value}

dn: ${service_ou},${base_dn}
objectClass: top
objectClass: organizationalUnit
ou: ${service_ou_value}
EOF
)

   if [[ "$enable_jenkins" == "1" && -n "$jenkins_password" ]]; then
      _LDAP_LDIF_CONTENT+=$'\n'
      _LDAP_LDIF_CONTENT+=$(cat <<EOF
dn: cn=jenkins-admins,${group_ou},${base_dn}
objectClass: top
objectClass: groupOfNames
cn: jenkins-admins
member: ${LDAP_BINDDN}
member: ${jenkins_user_dn}
EOF
)
      _LDAP_LDIF_CONTENT+=$'
'
      _LDAP_LDIF_CONTENT+=$(cat <<EOF
dn: ${jenkins_user_dn}
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: person
cn: Jenkins Admin
sn: Admin
uid: jenkins-admin
userPassword: ${jenkins_password}
EOF
)
   fi
}

function _ldap_seed_ldif_secret() {
   [[ "${LDAP_LDIF_ENABLED:-false}" == "true" ]] || return 0
   [[ -n "${LDAP_LDIF_VAULT_PATH:-}" ]] || { _warn "[ldap] LDIF sync enabled but LDAP_LDIF_VAULT_PATH is empty; skipping seed"; return 0; }

   local vault_ns="${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}"
   local vault_release="${VAULT_RELEASE:-${VAULT_RELEASE_DEFAULT:-vault}}"
   local mount="${LDAP_VAULT_KV_MOUNT:-secret}"
   local vault_path="${LDAP_LDIF_VAULT_PATH}"
   local content_key="${LDAP_LDIF_CONTENT_KEY:-content}"
   local full_path="${mount}/${vault_path}"

   if _vault_exec --no-exit "$vault_ns" "vault kv get ${full_path}" "$vault_release" >/dev/null 2>&1; then
      _info "[ldap] refreshing Vault LDIF ${full_path}"
   else
      _info "[ldap] seeding Vault LDIF ${full_path}"
   fi

   local base_dn="${LDAP_VAULT_BASE_DN:-${LDAP_BASE_DN}}"
   local org_name="${LDAP_VAULT_ORG_NAME:-${LDAP_ORG_NAME}}"
   local dc_primary="${LDAP_DC_PRIMARY}"
   local group_ou="${LDAP_GROUP_OU}"
   local service_ou="${LDAP_SERVICE_OU}"
   local enable_jenkins="${ENABLE_JENKINS:-0}"
   local jenkins_user_dn="uid=jenkins-admin,${service_ou},${base_dn}"
   local jenkins_password=""
   if [[ "$enable_jenkins" == "1" ]]; then
      local jenkins_secret_json=""
      local _jenkins_vault_path="${mount}/${JENKINS_ADMIN_VAULT_PATH:-eso/jenkins-admin}"
      jenkins_secret_json=$(_vault_exec --no-exit "$vault_ns" "vault kv get -format=json -- '${_jenkins_vault_path}'" "$vault_release" 2>/dev/null || true)
      if [[ -n "$jenkins_secret_json" ]]; then
         jenkins_password=$(printf '%s' "$jenkins_secret_json" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("data",{}).get("data",{}).get("password",""))' 2>/dev/null || true)
      fi
   fi

   _ldap_build_ldif_content       "$base_dn" "$org_name" "$dc_primary"       "$group_ou" "$service_ou"       "$enable_jenkins" "$jenkins_password" "$jenkins_user_dn" || return 1
   local ldif_content="$_LDAP_LDIF_CONTENT"

   if declare -f secret_backend_put >/dev/null 2>&1; then
      export VAULT_SECRET_BACKEND_NS="$vault_ns"
      export VAULT_SECRET_BACKEND_RELEASE="$vault_release"
      export VAULT_SECRET_BACKEND_MOUNT="${mount}"
      if secret_backend_put "$vault_path" "${content_key}=${ldif_content}"; then
         _info "[ldap] seeded Vault LDIF ${full_path}"
         return 0
      fi
   else
      local script
      printf -v script "cat <<'EOF_LDIF' | vault kv put %s %s=-
%s
EOF_LDIF" "$full_path" "$content_key" "$ldif_content"
      if _vault_exec --no-exit "$vault_ns" "$script" "$vault_release"; then
         _info "[ldap] seeded Vault LDIF ${full_path}"
         return 0
      fi
   fi

   _err "[ldap] unable to seed Vault LDIF ${full_path}"
}

function _ldap_wait_for_secret() {
   local ns="${1:-$LDAP_NAMESPACE}"
   local secret="${2:-$LDAP_ADMIN_SECRET_NAME}"
   local timeout="${3:-60}"
   local interval=3
   local elapsed=0

   if [[ -z "$secret" ]]; then
      _err "[ldap] secret name required for wait"
   fi

   _info "[ldap] waiting for secret ${ns}/${secret}"
   while (( elapsed < timeout )); do
      if _kubectl --no-exit -n "$ns" get secret "$secret" >/dev/null 2>&1; then
         _info "[ldap] secret ${ns}/${secret} available"
         return 0
      fi
      sleep "$interval"
      elapsed=$(( elapsed + interval ))
   done

   _err "[ldap] timed out waiting for secret ${ns}/${secret}"
}

function _ldap_deploy_chart() {
   local ns="${1:-$LDAP_NAMESPACE}"
   local release="${2:-$LDAP_RELEASE}"
   local version="${3:-${LDAP_HELM_CHART_VERSION:-}}"

   local helm_repo_name_default="johanneskastl-openldap-bitnami"
   local helm_repo_name="${LDAP_HELM_REPO_NAME:-$helm_repo_name_default}"
   local helm_repo_url_default="https://johanneskastl.github.io/openldap-bitnami-helm-chart/"
   local helm_repo_url="${LDAP_HELM_REPO_URL:-$helm_repo_url_default}"
   local helm_chart_ref_default="${helm_repo_name_default}/openldap-bitnami"

   local chart_archive_candidate="${LDAP_HELM_CHART_ARCHIVE:-}"
   if [[ -z "$chart_archive_candidate" ]]; then
      if [[ -n "$version" ]]; then
         chart_archive_candidate="${LDAP_CONFIG_DIR}/openldap-chart-${version}.tgz"
      else
         chart_archive_candidate="${LDAP_CONFIG_DIR}/openldap-chart.tgz"
      fi
   fi

   _ldap_resolve_chart_ref       "$helm_chart_ref_default" "$helm_repo_name" "$helm_repo_url"       "$version" "$chart_archive_candidate"
   local helm_chart_ref="$_LDAP_CHART_REF"
   local skip_repo_ops="$_LDAP_CHART_SKIP_REPO_OPS"
   local is_oci_ref="$_LDAP_CHART_IS_OCI"

   if (( ! skip_repo_ops )); then
      _helm repo add "$helm_repo_name" "$helm_repo_url"
      if ! _helm --no-exit repo update "$helm_repo_name" >/dev/null 2>&1; then
         _warn "[ldap] failed to update Helm repo ${helm_repo_name}; provide LDAP_HELM_CHART_REF or LDAP_HELM_CHART_ARCHIVE pointing to a local chart when working offline."
      fi
   fi

   local values_template="$LDAP_CONFIG_DIR/values.yaml.tmpl"
   local values_rendered
   values_rendered=$(_ldap_render_template "$values_template" "ldap-values") || return 1

   _ldap_ensure_helm_chart_available "$helm_chart_ref" "$version" "$helm_repo_name" "$skip_repo_ops" "$is_oci_ref" || return 1

   local -a args=(upgrade --install "$release" "$helm_chart_ref" -n "$ns" -f "$values_rendered" --create-namespace)
   if [[ -n "$version" ]]; then
      args+=("--version" "$version")
   fi

   local helm_rc=0
   if ! _helm "${args[@]}"; then
      helm_rc=$?
   fi

   if (( helm_rc == 0 )); then
      if [[ -f "$values_rendered" ]]; then
         local cm_yaml
         cm_yaml=$(cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: openldap-values
  namespace: $ns
data:
  values.yaml: |
$(sed 's/^/    /' "$values_rendered")
EOF
)
         printf '%s
' "$cm_yaml" | _kubectl apply -f - >/dev/null 2>&1 ||             _warn "[ldap] unable to persist rendered values in ConfigMap openldap-values"
      else
         _warn "[ldap] rendered values file missing; skipping ConfigMap update"
      fi
   fi

   _cleanup_on_success "$values_rendered"
   return "$helm_rc"
}


# _ldap_fetch_import_prereqs
# Reads admin password and pod name needed for LDIF import.
# Sets globals: _LDAP_IMPORT_ADMIN_PASS _LDAP_IMPORT_POD
# Args: $1=ns $2=release $3=admin_secret $4=admin_key
function _ldap_fetch_import_prereqs() {
   local ns="$1" release="$2" admin_secret="$3" admin_key="$4"

   local admin_pass=""
   admin_pass=$(_no_trace _kubectl --no-exit -n "$ns" get secret "$admin_secret" -o jsonpath="{.data.${admin_key}}" 2>/dev/null || true)
   if [[ -z "$admin_pass" ]]; then
      _warn "[ldap] unable to read ${admin_key} from secret ${ns}/${admin_secret}; skipping LDIF import"
      return 1
   fi
   admin_pass=$(_no_trace bash -c 'printf %s "$1" | base64 -d 2>/dev/null | tr -d "\n"' _ "$admin_pass")
   if [[ -z "$admin_pass" ]]; then
      _warn "[ldap] decoded admin password empty; skipping LDIF import"
      return 1
   fi

   local pod=""
   pod=$(_kubectl --no-exit -n "$ns" get pod -l "app.kubernetes.io/name=openldap-bitnami,app.kubernetes.io/instance=${release}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
   if [[ -z "$pod" ]]; then
      _warn "[ldap] no OpenLDAP pod found for release ${ns}/${release}; skipping LDIF import"
      return 1
   fi

   _LDAP_IMPORT_ADMIN_PASS="$admin_pass"
   _LDAP_IMPORT_POD="$pod"
}

function _ldap_import_ldif() {
   local ns="${1:-$LDAP_NAMESPACE}"
   local release="${2:-$LDAP_RELEASE}"
   local ldif_secret="${LDAP_LDIF_SECRET_NAME:-openldap-bitnami-ldif-import}"
   local ldif_mount_path="${LDAP_LDIF_MOUNT_PATH:-/ldif_import/bootstrap.ldif}"
   local admin_secret="${LDAP_ADMIN_SECRET_NAME:-openldap-admin}"
   local admin_key="${LDAP_ADMIN_PASSWORD_KEY:-LDAP_ADMIN_PASSWORD}"
   local admin_user="${LDAP_ADMIN_USERNAME:-ldap-admin}"
   local base_dn="${LDAP_BASE_DN:-dc=${LDAP_DC_PRIMARY:-home},dc=${LDAP_DC_SECONDARY:-org}}"
   local admin_dn="cn=${admin_user},${base_dn}"
   local deploy_name="${release}-openldap-bitnami"
   local ldap_port="1389"

   [[ "${LDAP_LDIF_ENABLED:-false}" == "true" ]] || return 0
   [[ -n "${LDAP_LDIF_VAULT_PATH:-}" ]] || { _warn "[ldap] LDIF sync enabled but LDAP_LDIF_VAULT_PATH is empty; skipping LDIF import"; return 0; }

   if ! _kubectl --no-exit -n "$ns" get secret "$ldif_secret" >/dev/null 2>&1; then
      _info "[ldap] LDIF secret ${ns}/${ldif_secret} not found; skipping LDIF import"
      return 0
   fi

   _ldap_fetch_import_prereqs "$ns" "$release" "$admin_secret" "$admin_key" || return $?
   local admin_pass="$_LDAP_IMPORT_ADMIN_PASS"
   local pod="$_LDAP_IMPORT_POD"

   if ! _kubectl --no-exit -n "$ns" exec "$pod" -- test -f "$ldif_mount_path" >/dev/null 2>&1; then
      _info "[ldap] LDIF file not found at ${ldif_mount_path} in pod; skipping LDIF import"
      return 0
   fi

   _info "[ldap] checking if LDIF entries already exist..."
   local search_result="" search_output=""
   search_output=$(_no_trace _kubectl --no-exit -n "$ns" exec "$pod" --       ldapsearch -x -H "ldap://localhost:${ldap_port}"       -D "$admin_dn" -w "$admin_pass"       -b "$base_dn" -LLL dn 2>/dev/null || true)
   search_result=$(echo "$search_output" | grep -c "^dn:" || true)
   if (( search_result > 1 )); then
      _info "[ldap] LDIF entries already exist (found $search_result entries); skipping import"
   else
      _info "[ldap] importing LDIF from ${ldif_mount_path}..."
      local import_output=""
      if import_output=$(_no_trace _kubectl --no-exit -n "$ns" exec "$pod" --          ldapadd -c -x -H "ldap://localhost:${ldap_port}"          -D "$admin_dn" -w "$admin_pass"          -f "$ldif_mount_path" 2>&1); then
         _info "[ldap] LDIF import completed successfully"
      else
         import_output=${import_output//$'
'/}
         if echo "$import_output" | grep -qE "Already exists|no global superior knowledge"; then
            _info "[ldap] LDIF import completed (some entries skipped - base DN or duplicates)"
         else
            _warn "[ldap] LDIF import encountered errors:"; echo "$import_output" | head -10
            _warn "[ldap] LDIF import failed; continuing with smoke test"
         fi
      fi
      search_result=$(_no_trace _kubectl --no-exit -n "$ns" exec "$pod" --          ldapsearch -x -H "ldap://localhost:${ldap_port}"          -D "$admin_dn" -w "$admin_pass"          -b "$base_dn" -LLL dn 2>/dev/null | grep -c "^dn:" || echo "0")
      _info "[ldap] LDIF import verification: found $search_result entries in directory"
   fi

   _info "[ldap] resetting test user passwords with unique passwords..."
   local test_users=("chengkai.liang" "jenkins-admin" "test-user")
   local user_ou="ou=users"
   local vault_ns="${VAULT_NS:-vault}"
   for user in "${test_users[@]}"; do
      local user_dn="cn=${user},${user_ou},${base_dn}"
      _kubectl --no-exit -n "$ns" exec "$pod" --          ldapsearch -x -H "ldap://localhost:${ldap_port}"          -D "$admin_dn" -w "$admin_pass"          -b "$user_dn" -LLL dn 2>/dev/null | grep -q "^dn:" || continue
      local vault_path="ldap/users/${user}"
      local existing_pass
      existing_pass=$(_no_trace _vault_exec "$vault_ns" "vault kv get -field=password secret/$vault_path" 2>/dev/null) || existing_pass=""
      local user_password="$existing_pass"
      if [[ -n "$user_password" ]]; then
         _info "[ldap] using existing password from Vault for $user"
      else
         user_password=$(openssl rand -base64 18 | tr -d '/+=' | head -c 20)
         _info "[ldap] generated new password for $user"
         printf -v put_cmd 'vault kv put secret/%s username=%q password=%q dn=%q'             "$vault_path" "$user" "$user_password" "$user_dn"
         _no_trace _vault_exec "$vault_ns" "$put_cmd" >/dev/null 2>&1 ||             _warn "[ldap] failed to store password in Vault for $user"
      fi
      _info "[ldap] setting password for $user_dn"
      _no_trace _kubectl --no-exit -n "$ns" exec "$pod" --          ldappasswd -x -H "ldap://localhost:${ldap_port}"          -D "$admin_dn" -w "$admin_pass"          -s "$user_password" "$user_dn" >/dev/null 2>&1 ||          _warn "[ldap] failed to set password for $user_dn"
   done

   return 0
}

# Get LDAP user password from Vault
# Usage: ldap_get_user_password <username>
# Example: ldap_get_user_password chengkai.liang
function ldap_get_user_password() {
   local username="${1:?Username required}"
   local vault_ns="${VAULT_NS:-vault}"
   local vault_path="ldap/users/${username}"

   local password
   password=$(_no_trace _vault_exec "$vault_ns" "vault kv get -field=password secret/$vault_path" 2>/dev/null) || {
      echo "Error: Password not found for user '$username' in Vault" >&2
      return 1
   }

   echo "$password"
}

# _ldap_read_sync_creds
# Reads and decodes admin/config passwords from secret.
# Sets globals: _LDAP_SYNC_ADMIN_PASS _LDAP_SYNC_CONFIG_PASS
# Args: $1=ns $2=secret $3=admin_key $4=config_key
function _ldap_read_sync_creds() {
   local ns="$1" secret="$2" admin_key="$3" config_key="$4"

   local admin_pass=""
   admin_pass=$(_no_trace _kubectl --no-exit -n "$ns" get secret "$secret" -o jsonpath="{.data.${admin_key}}" 2>/dev/null || true)
   if [[ -z "$admin_pass" ]]; then
      _warn "[ldap] unable to read ${admin_key} from secret ${ns}/${secret}; skipping admin password sync"
      return 1
   fi
   admin_pass=$(_no_trace bash -c 'printf %s "$1" | base64 -d 2>/dev/null | tr -d "\n"' _ "$admin_pass")
   if [[ -z "$admin_pass" ]]; then
      _warn "[ldap] decoded admin password empty; skipping admin password sync"
      return 1
   fi

   local config_pass=""
   config_pass=$(_no_trace _kubectl --no-exit -n "$ns" get secret "$secret" -o jsonpath="{.data.${config_key}}" 2>/dev/null || true)
   if [[ -z "$config_pass" ]]; then
      _warn "[ldap] unable to read ${config_key} from secret ${ns}/${secret}; skipping admin password sync"
      return 1
   fi
   config_pass=$(_no_trace bash -c 'printf %s "$1" | base64 -d 2>/dev/null | tr -d "\n"' _ "$config_pass")
   if [[ -z "$config_pass" ]]; then
      _warn "[ldap] decoded config password empty; skipping admin password sync"
      return 1
   fi

   _LDAP_SYNC_ADMIN_PASS="$admin_pass"
   _LDAP_SYNC_CONFIG_PASS="$config_pass"
}

function _ldap_sync_admin_password() {
   local ns="${1:-$LDAP_NAMESPACE}"
   local release="${2:-$LDAP_RELEASE}"
   local secret="${LDAP_ADMIN_SECRET_NAME:-openldap-admin}"
   local admin_key="${LDAP_ADMIN_PASSWORD_KEY:-LDAP_ADMIN_PASSWORD}"
   local config_key="${LDAP_CONFIG_PASSWORD_KEY:-LDAP_CONFIG_PASSWORD}"
   local admin_user="${LDAP_ADMIN_USERNAME:-ldap-admin}"
   local base_dn="${LDAP_BASE_DN:-dc=${LDAP_DC_PRIMARY:-home},dc=${LDAP_DC_SECONDARY:-org}}"
   local admin_dn="${LDAP_BINDDN:-cn=${admin_user},${base_dn}}"
   local config_dn_override="${LDAP_CONFIG_ADMIN_DN:-}"

   _ldap_read_sync_creds "$ns" "$secret" "$admin_key" "$config_key" || return 1
   local admin_pass="$_LDAP_SYNC_ADMIN_PASS"
   local config_pass="$_LDAP_SYNC_CONFIG_PASS"

   local pod=""
   pod=$(_kubectl --no-exit -n "$ns" get pod -l "app.kubernetes.io/instance=${release},app.kubernetes.io/name=openldap-bitnami" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
   if [[ -z "$pod" ]]; then
      _warn "[ldap] unable to locate pod for release ${release} in namespace ${ns}; skipping admin password sync"
      return 1
   fi

   local sync_cmd
   sync_cmd=$(cat <<'EOS'
set -euo pipefail
export PATH="/opt/bitnami/openldap/bin:$PATH"
CONFIG_DN_VAR="${CONFIG_DN_OVERRIDE:-}"
CONFIG_DN_VAR="${CONFIG_DN_VAR:-$(printenv LDAP_CONFIG_ADMIN_DN 2>/dev/null || true)}"
CONFIG_DN_VAR="${CONFIG_DN_VAR:-cn=admin,cn=config}"
ADMIN_CN_VAR="${ADMIN_CN_OVERRIDE:-}"
ADMIN_CN_VAR="${ADMIN_CN_VAR:-$(printenv LDAP_ADMIN_USERNAME 2>/dev/null || true)}"
ADMIN_CN_VAR="${ADMIN_CN_VAR:-ldap-admin}"
ADMIN_DN_VAR="$ADMIN_DN"
SEARCH_DN=$(LDAPTLS_REQCERT=never ldapsearch -x -H ldap://127.0.0.1:1389   -D "$CONFIG_DN_VAR" -w "$CONFIG_PASS"   -b "$BASE_DN" "(cn=${ADMIN_CN_VAR})" dn 2>/dev/null | awk 'tolower($1)=="dn:" {sub(/^dn:[[:space:]]*/,""); print; exit}')
ADMIN_DN_VAR="${SEARCH_DN:-$ADMIN_DN_VAR}"
command -v ldappasswd >/dev/null 2>&1 &&   LDAPTLS_REQCERT=never ldappasswd -x -H ldap://127.0.0.1:1389     -D "$CONFIG_DN_VAR" -w "$CONFIG_PASS"     "$ADMIN_DN_VAR" -s "$ADMIN_PASS" ||   LDAPTLS_REQCERT=never ldapmodify -x -H ldap://127.0.0.1:1389     -D "$CONFIG_DN_VAR" -w "$CONFIG_PASS" <<EOF
dn: $ADMIN_DN_VAR
changetype: modify
replace: userPassword
userPassword: $ADMIN_PASS
EOF

LDAPTLS_REQCERT=never ldapwhoami -x -H ldap://127.0.0.1:1389   -D "$ADMIN_DN_VAR" -w "$ADMIN_PASS" >/dev/null 2>&1 || {
  printf 'VERIFY_FAIL:%s
' "$ADMIN_DN_VAR"
  exit 2
}

printf 'SYNC_OK:%s
' "$ADMIN_DN_VAR"
EOS
)

   local sync_output=""
   if ! sync_output=$(printf '%s
' "$sync_cmd" | _no_trace _kubectl --no-exit -n "$ns" exec "$pod" -- env ADMIN_DN="$admin_dn" ADMIN_PASS="$admin_pass" CONFIG_PASS="$config_pass" CONFIG_DN_OVERRIDE="${config_dn_override}" ADMIN_CN_OVERRIDE="$admin_user" BASE_DN="$base_dn" bash -s 2>&1); then
      sync_output=${sync_output//$'
'/}
      if [[ "$sync_output" == *VERIFY_FAIL:* ]]; then
         local verified_dn="${sync_output##*VERIFY_FAIL:}"
         _warn "[ldap] unable to verify admin password for ${verified_dn}"
      else
         _warn "[ldap] unable to reconcile admin password (${sync_output})"
      fi
      return 1
   fi

   sync_output=${sync_output//$'
'/}
   local reconciled_dn="$admin_dn"
   if [[ "$sync_output" == SYNC_OK:* ]]; then
      reconciled_dn="${sync_output#SYNC_OK:}"
   fi
   export LDAP_BINDDN="$reconciled_dn"
   _info "[ldap] reconciled admin password for ${reconciled_dn}"
   return 0
}


function _ldap_deploy_password_rotator() {
   local ns="${1:?Namespace required}"
   local template="${SCRIPT_DIR}/etc/ldap/ldap-password-rotator.yaml.tmpl"
   local vault_ns="${VAULT_NS:-vault}"

   _info "[ldap] deploying password rotation CronJob"

   if [[ ! -f "$template" ]]; then
      _warn "[ldap] password rotator template not found: $template"
      return 1
   fi

   # Export required variables for envsubst
   export LDAP_NAMESPACE="$ns"
   export VAULT_NAMESPACE="$vault_ns"
   export LDAP_ROTATOR_IMAGE="${LDAP_ROTATOR_IMAGE}"
   export LDAP_ROTATION_SCHEDULE="${LDAP_ROTATION_SCHEDULE}"
   export LDAP_POD_LABEL="${LDAP_POD_LABEL}"
   export LDAP_PORT="${LDAP_ROTATION_PORT:-1389}"
   export LDAP_BASE_DN="${LDAP_BASE_DN}"
   export LDAP_ADMIN_DN="${LDAP_BIND_DN}"
   export LDAP_USER_OU="${LDAP_USER_OU}"
   # Force internal Vault address for rotation job (ignore external VAULT_ADDR from environment)
   export VAULT_ADDR="http://vault.vault.svc:8200"
   export VAULT_ROOT_TOKEN_SECRET="${VAULT_ROOT_TOKEN_SECRET:-vault-root}"
   export VAULT_ROOT_TOKEN_KEY="${VAULT_ROOT_TOKEN_KEY:-root_token}"
   export USERS_TO_ROTATE="${LDAP_USERS_TO_ROTATE}"

   # Use envsubst with explicit variable list to avoid substituting shell variables in the script
   # Only substitute these template variables, leave all other $ alone
   local envsubst_vars='$LDAP_NAMESPACE $VAULT_NAMESPACE $LDAP_ROTATOR_IMAGE $LDAP_ROTATION_SCHEDULE $LDAP_POD_LABEL $LDAP_PORT $LDAP_BASE_DN $LDAP_ADMIN_DN $LDAP_USER_OU $VAULT_ADDR $VAULT_ROOT_TOKEN_SECRET $VAULT_ROOT_TOKEN_KEY $USERS_TO_ROTATE'

   if envsubst "$envsubst_vars" < "$template" | _kubectl apply -f - >/dev/null 2>&1; then
      _info "[ldap] password rotator deployed (schedule: ${LDAP_ROTATION_SCHEDULE})"
      return 0
   else
      _warn "[ldap] failed to deploy password rotator"
      return 1
   fi
}

function _ldap_parse_deploy_opts() {
   _LDAP_DEPLOY_NAMESPACE=""
   _LDAP_DEPLOY_RELEASE=""
   _LDAP_DEPLOY_CHART_VERSION=""
   _LDAP_DEPLOY_ENABLE_VAULT=0
   _LDAP_DEPLOY_RESTORE_TRACE=0

   case $- in *x*) _LDAP_DEPLOY_RESTORE_TRACE=1 ;; esac

   while [[ $# -gt 0 ]]; do
      case "$1" in
         -h|--help)
            cat <<EOF
Usage: deploy_ldap [options] [namespace] [release] [chart-version]

Options:
  --namespace <ns>         Kubernetes namespace (default: ${LDAP_NAMESPACE})
  --release <name>         Helm release name (default: ${LDAP_RELEASE})
  --chart-version <ver>    Helm chart version (default: ${LDAP_HELM_CHART_VERSION:-<auto>})
  --enable-vault           Deploy Vault and ESO if not already deployed
  -h, --help               Show this help message

Positional overrides (deprecated):
  namespace                Equivalent to --namespace <ns>
  release                  Equivalent to --release <name>
  chart-version            Equivalent to --chart-version <ver>

Examples:
  deploy_ldap
  deploy_ldap --enable-vault
  deploy_ldap --namespace my-ns
EOF
            if (( _LDAP_DEPLOY_RESTORE_TRACE )); then set -x; fi
            return 0
            ;;
         --enable-vault) _LDAP_DEPLOY_ENABLE_VAULT=1; shift; continue ;;
         --namespace)
            [[ -z "${2:-}" ]] && { _err "[ldap] --namespace flag requires an argument"; return 1; }
            _LDAP_DEPLOY_NAMESPACE="$2"; shift 2; continue ;;
         --namespace=*)
            _LDAP_DEPLOY_NAMESPACE="${1#*=}"; [[ -z "$_LDAP_DEPLOY_NAMESPACE" ]] && { _err "[ldap] --namespace flag requires an argument"; return 1; }
            shift; continue ;;
         --release)
            [[ -z "${2:-}" ]] && { _err "[ldap] --release flag requires an argument"; return 1; }
            _LDAP_DEPLOY_RELEASE="$2"; shift 2; continue ;;
         --release=*)
            _LDAP_DEPLOY_RELEASE="${1#*=}"; [[ -z "$_LDAP_DEPLOY_RELEASE" ]] && { _err "[ldap] --release flag requires an argument"; return 1; }
            shift; continue ;;
         --chart-version)
            [[ -z "${2:-}" ]] && { _err "[ldap] --chart-version flag requires an argument"; return 1; }
            _LDAP_DEPLOY_CHART_VERSION="$2"; shift 2; continue ;;
         --chart-version=*)
            _LDAP_DEPLOY_CHART_VERSION="${1#*=}"; [[ -z "$_LDAP_DEPLOY_CHART_VERSION" ]] && { _err "[ldap] --chart-version flag requires an argument"; return 1; }
            shift; continue ;;
         --) shift; break ;;
         -*) _err "[ldap] unknown option: $1"; return 1 ;;
         *)
            if [[ -z "$_LDAP_DEPLOY_NAMESPACE" ]]; then
               _LDAP_DEPLOY_NAMESPACE="$1"
            elif [[ -z "$_LDAP_DEPLOY_RELEASE" ]]; then
               _LDAP_DEPLOY_RELEASE="$1"
            elif [[ -z "$_LDAP_DEPLOY_CHART_VERSION" ]]; then
               _LDAP_DEPLOY_CHART_VERSION="$1"
            else
               _err "[ldap] unexpected argument: $1"; return 1
            fi
            ;;
      esac
      shift
   done

   _LDAP_DEPLOY_NAMESPACE="${_LDAP_DEPLOY_NAMESPACE:-$LDAP_NAMESPACE}"
   _LDAP_DEPLOY_RELEASE="${_LDAP_DEPLOY_RELEASE:-$LDAP_RELEASE}"
   _LDAP_DEPLOY_CHART_VERSION="${_LDAP_DEPLOY_CHART_VERSION:-${LDAP_HELM_CHART_VERSION:-}}"
   if [[ -z "$_LDAP_DEPLOY_NAMESPACE" ]]; then
      _err "[ldap] namespace is required"; return 1
   fi
}

function _ldap_deploy_prerequisites() {
   local tag="${1:-ldap}"
   _info "[${tag}] deploying prerequisites (--enable-vault specified)"
   if ! deploy_eso; then
      _err "[${tag}] ESO deployment failed"
      return 1
   fi
   _info "[${tag}] waiting for ESO webhook to be ready..."
   if ! _kubectl --no-exit -n "${ESO_NAMESPACE:-secrets}" wait --for=condition=available deployment/external-secrets-webhook --timeout=60s; then
      _err "[${tag}] ESO webhook did not become ready"
      return 1
   fi
   if ! deploy_vault; then
      _err "[${tag}] Vault deployment failed"
      return 1
   fi
}

function _ldap_ensure_vault_ready() {
   local vault_ns="$1" vault_release="$2"
   if _vault_is_sealed "$vault_ns" "$vault_release"; then
      _info "[ldap] Vault ${vault_ns}/${vault_release} is sealed; attempting to unseal"
      if ! _vault_replay_cached_unseal "$vault_ns" "$vault_release"; then
         _err "[ldap] Vault ${vault_ns}/${vault_release} is sealed and cannot be unsealed"
      fi
   else
      local seal_check_rc=$?
      if (( seal_check_rc == 2 )); then
         _warn "[ldap] Unable to determine Vault seal status; attempting unseal as fallback"
         if ! _vault_replay_cached_unseal "$vault_ns" "$vault_release"; then
            _err "[ldap] Cannot access Vault ${vault_ns}/${vault_release}"
         fi
      else
         _info "[ldap] Vault ${vault_ns}/${vault_release} is already unsealed"
      fi
   fi
}

function _ldap_run_post_deploy() {
   local namespace="$1" release="$2" deploy_name="$3" smoke_port="$4"

   if ! _kubectl --no-exit -n "$namespace" rollout status "deployment/${deploy_name}" --timeout=180s; then
      _warn "[ldap] deployment ${namespace}/${deploy_name} not ready; skipping smoke test"
      return 0
   fi

   if ! _ldap_sync_admin_password "$namespace" "$release"; then
      _warn "[ldap] admin password sync failed; continuing with smoke test"
   fi

   if ! _ldap_import_ldif "$namespace" "$release"; then
      _warn "[ldap] LDIF import failed; continuing with smoke test"
   fi

   if (( LDAP_ROTATOR_ENABLED )); then
      if ! _ldap_deploy_password_rotator "$namespace"; then
         _warn "[ldap] password rotator deployment failed"
      fi
   fi

   local smoke_script="${SCRIPT_DIR}/tests/plugins/openldap.sh"
   local service_name="${LDAP_SERVICE_NAME:-${release}-openldap-bitnami}"
   if [[ -x "$smoke_script" ]]; then
      "$smoke_script" "$namespace" "$release" "$service_name" "$smoke_port" "$LDAP_BASE_DN" || _warn "[ldap] smoke test failed; inspect output above"
   elif [[ -r "$smoke_script" ]]; then
      bash "$smoke_script" "$namespace" "$release" "$service_name" "$smoke_port" "$LDAP_BASE_DN" || _warn "[ldap] smoke test failed; inspect output above"
   else
      _warn "[ldap] smoke test helper missing at ${smoke_script}; skipping verification"
   fi
}

function deploy_ldap() {
   _ldap_parse_deploy_opts "$@" || return $?
   local namespace="$_LDAP_DEPLOY_NAMESPACE"
   local release="$_LDAP_DEPLOY_RELEASE"
   local chart_version="$_LDAP_DEPLOY_CHART_VERSION"
   local enable_vault="$_LDAP_DEPLOY_ENABLE_VAULT"
   local restore_trace="$_LDAP_DEPLOY_RESTORE_TRACE"

   if [[ "${CLUSTER_ROLE:-infra}" == "app" ]]; then
      _info "[ldap] CLUSTER_ROLE=app — skipping deploy_ldap"
      (( restore_trace )) && set -x
      return 0
   fi

   (( restore_trace )) && set -x
   export LDAP_NAMESPACE="$namespace"
   export LDAP_RELEASE="$release"

   if (( enable_vault )); then
      _ldap_deploy_prerequisites "ldap" || return 1
   fi

   local vault_ns="${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}"
   local vault_release="${VAULT_RELEASE:-${VAULT_RELEASE_DEFAULT:-vault}}"
   _vault_login "$vault_ns" "$vault_release"
   _ldap_ensure_vault_ready "$vault_ns" "$vault_release"

   _ldap_seed_admin_secret || return 1
   _ldap_seed_ldif_secret || return 1

   _vault_configure_secret_reader_role       "$vault_ns" "$vault_release"       "$LDAP_ESO_SERVICE_ACCOUNT" "$namespace"       "$LDAP_VAULT_KV_MOUNT" "$LDAP_VAULT_POLICY_PREFIX" "$LDAP_ESO_ROLE" ||       { _err "[ldap] failed to configure Vault role ${LDAP_ESO_ROLE} for namespace ${namespace}"; return 1; }

   _ldap_ensure_namespace "$namespace" || return 1
   _ldap_apply_eso_resources "$namespace" || return 1
   _ldap_wait_for_secret "$namespace" "${LDAP_ADMIN_SECRET_NAME}" || { _err "[ldap] Vault-sourced secret ${LDAP_ADMIN_SECRET_NAME} not available"; return 1; }

   if [[ "${LDAP_LDIF_ENABLED:-false}" == "true" && -n "${LDAP_LDIF_VAULT_PATH:-}" ]]; then
      _ldap_wait_for_secret "$namespace" "${LDAP_LDIF_SECRET_NAME}" ||          { _err "[ldap] Vault-sourced LDIF secret ${LDAP_LDIF_SECRET_NAME} not available"; return 1; }
   fi

   local deploy_rc=0
   _ldap_deploy_chart "$namespace" "$release" "$chart_version" || deploy_rc=$?

   if (( deploy_rc == 0 )); then
      local deploy_name="${release}-openldap-bitnami"
      local smoke_port="${LDAP_SMOKE_PORT:-3389}"
      _ldap_run_post_deploy "$namespace" "$release" "$deploy_name" "$smoke_port"
   fi

   (( restore_trace )) && set -x
   return "$deploy_rc"
}



# Deploy OpenLDAP with Active Directory-compatible schema for testing
# This is a convenience wrapper that auto-configures AD schema settings
# and runs fail-fast smoke tests
# _ldap_run_ad_smoke_test
function _ldap_run_ad_smoke_test() {
   local namespace="$1" release="$2" smoke_port="$3"
   local service_name="${LDAP_SERVICE_NAME:-${release}-openldap-bitnami}"
   local smoke_script="${SCRIPT_DIR}/tests/plugins/openldap.sh"
   if [[ -x "$smoke_script" ]]; then
      "$smoke_script" "$namespace" "$release" "$service_name" "$smoke_port" "$LDAP_BASE_DN" || _warn "[ad] smoke test failed; inspect output above"
   elif [[ -r "$smoke_script" ]]; then
      bash "$smoke_script" "$namespace" "$release" "$service_name" "$smoke_port" "$LDAP_BASE_DN" || _warn "[ad] smoke test failed; inspect output above"
   else
      _warn "[ad] smoke test helper missing at ${smoke_script}; skipping"
   fi
}

function deploy_ad() {
   local enable_vault=0
   local namespace=""
   local release=""
   local args=()

   while [[ $# -gt 0 ]]; do
      case "$1" in
         -h|--help)
            cat <<'EOF'
Usage: deploy_ad [options] [namespace] [release]

Deploy OpenLDAP with AD-compatible schema for LOCAL TESTING.

Options:
  --namespace <ns>   Namespace (default: directory)
  --release <name>   Release name (default: openldap)
  --enable-vault     Deploy Vault + ESO prerequisites before LDAP
  -h, --help         Show this help message
EOF
            return 0
            ;;
         --enable-vault) enable_vault=1; shift; continue ;;
         --namespace) namespace="${2:?}"; args+=("$1" "$2"); shift 2; continue ;;
         --namespace=*) namespace="${1#*=}"; args+=("$1"); shift; continue ;;
         --release) release="${2:?}"; args+=("$1" "$2"); shift 2; continue ;;
         --release=*) release="${1#*=}"; args+=("$1"); shift; continue ;;
         *) args+=("$1"); shift; continue ;;
      esac
   done

   export LDAP_LDIF_FILE="${SCRIPT_DIR}/etc/ldap/bootstrap-ad-schema.ldif"
   export LDAP_BASE_DN="DC=corp,DC=example,DC=com"
   export LDAP_BINDDN="cn=admin,DC=corp,DC=example,DC=com"
   export LDAP_DOMAIN="corp.example.com"
   export LDAP_ROOT="DC=corp,DC=example,DC=com"
   export LDAP_USERDN="OU=ServiceAccounts,DC=corp,DC=example,DC=com"
   export LDAP_GROUPDN="OU=Groups,DC=corp,DC=example,DC=com"

   if (( enable_vault )); then
      _ldap_deploy_prerequisites "ad" || return 1
   fi

   if ! deploy_ldap "${args[@]}"; then
      _err "[ad] OpenLDAP deployment failed"
      return 1
   fi

   local final_ns="${LDAP_NAMESPACE:-directory}"
   local final_release="${LDAP_RELEASE:-openldap}"
   local smoke_port="${LDAP_SMOKE_PORT:-3389}"
   _ldap_run_ad_smoke_test "$final_ns" "$final_release" "$smoke_port"
   return 0
}
