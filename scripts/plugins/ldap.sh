LDAP_CONFIG_DIR="$SCRIPT_DIR/etc/ldap"
LDAP_VARS_FILE="$LDAP_CONFIG_DIR/vars.sh"

if [[ ! -r "$LDAP_VARS_FILE" ]]; then
   _err "[ldap] vars file missing: $LDAP_VARS_FILE"
else
   # shellcheck disable=SC1090
   source "$LDAP_VARS_FILE"
fi

VAULT_PLUGIN="$PLUGINS_DIR/vault.sh"
if [[ ! -r "$VAULT_PLUGIN" ]]; then
   _err "[ldap] missing required plugin: $VAULT_PLUGIN"
else
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
   local existing_json=""

   if ! _vault_exec --no-exit "$vault_ns" "vault status >/dev/null 2>&1" "$vault_release"; then
      _err "[ldap] Vault instance ${vault_ns}/${vault_release} unavailable or sealed; unseal before deploy"
   fi

   if existing_json=$(_vault_exec --no-exit "$vault_ns" "vault kv get -format=json ${full_path}" "$vault_release" 2>/dev/null); then
      existing_json=${existing_json//$'\r'/}
   else
      existing_json=""
   fi

   local admin_password=""
   local config_password=""
   local existing_username=""

   if [[ -n "$existing_json" ]]; then
      existing_username=$(printf '%s' "$existing_json" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("data",{}).get("data",{}).get(sys.argv[1],""))' "$username_key" 2>/dev/null || true)
      admin_password=$(printf '%s' "$existing_json" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("data",{}).get("data",{}).get(sys.argv[1],""))' "$password_key" 2>/dev/null || true)
      config_password=$(printf '%s' "$existing_json" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("data",{}).get("data",{}).get(sys.argv[1],""))' "$config_key" 2>/dev/null || true)
   fi

   local username="${existing_username:-$username}"

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

   local script
   printf -v script "cat <<'EOF' | vault kv put %s -\n%s\nEOF" \
      "$full_path" "$payload"

   if _vault_exec --no-exit "$vault_ns" "$script" "$vault_release"; then
      _info "[ldap] seeded Vault secret ${full_path}"
      return 0
   fi

   _err "[ldap] unable to seed Vault admin secret ${full_path}"
}

function _ldap_seed_ldif_secret() {
   if [[ "${LDAP_LDIF_ENABLED:-false}" != "true" ]]; then
      return 0
   fi

   if [[ -z "${LDAP_LDIF_VAULT_PATH:-}" ]]; then
      _warn "[ldap] LDIF sync enabled but LDAP_LDIF_VAULT_PATH is empty; skipping seed"
      return 0
   fi

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
   local group_ou_value="${group_ou#*=}"
   local service_ou_value="${service_ou#*=}"
   local jenkins_user_dn="uid=jenkins-admin,${service_ou},${base_dn}"
   local jenkins_password=""

   local jenkins_secret_json=""
   jenkins_secret_json=$(_vault_exec --no-exit "$vault_ns" "vault kv get -format=json ${mount}/${JENKINS_ADMIN_VAULT_PATH:-eso/jenkins-admin}" "$vault_release" 2>/dev/null || true)
   if [[ -n "$jenkins_secret_json" ]]; then
      jenkins_password=$(printf '%s' "$jenkins_secret_json" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("data",{}).get("data",{}).get("password",""))' 2>/dev/null || true)
   fi

   local group_members="member: ${LDAP_BINDDN}"
   if [[ -n "$jenkins_password" ]]; then
      group_members+=$'\n'"member: ${jenkins_user_dn}"
   fi

   local ldif_content
   ldif_content=$(cat <<EOF
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

dn: cn=jenkins-admins,${group_ou},${base_dn}
objectClass: top
objectClass: groupOfNames
cn: jenkins-admins
${group_members}
EOF
)

   if [[ -n "$jenkins_password" ]]; then
      ldif_content+=$'\n'
      ldif_content+=$(cat <<EOF
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

   local script
   printf -v script "cat <<'EOF_LDIF_SEED' | vault kv put %s %s=-\n%s\nEOF_LDIF_SEED" \
      "$full_path" "$content_key" "$ldif_content"

   if _vault_exec --no-exit "$vault_ns" "$script" "$vault_release"; then
      _info "[ldap] seeded Vault LDIF ${full_path}"
      return 0
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
   local helm_chart_ref="${LDAP_HELM_CHART_REF:-$helm_chart_ref_default}"
   local chart_archive_candidate="${LDAP_HELM_CHART_ARCHIVE:-}"
   local chart_archive=""

   if [[ -z "$chart_archive_candidate" ]]; then
      if [[ -n "$version" ]]; then
         chart_archive_candidate="${LDAP_CONFIG_DIR}/openldap-chart-${version}.tgz"
      else
         chart_archive_candidate="${LDAP_CONFIG_DIR}/openldap-chart.tgz"
      fi
   fi

   if [[ -n "$chart_archive_candidate" && -f "$chart_archive_candidate" ]]; then
      chart_archive="$chart_archive_candidate"
   fi

   if [[ -n "$chart_archive" ]]; then
      local archive_dir archive_name
      archive_dir="$(cd "$(dirname "$chart_archive")" >/dev/null 2>&1 && pwd)"
      archive_name="$(basename "$chart_archive")"
      chart_archive="${archive_dir}/${archive_name}"
      helm_chart_ref="$chart_archive"
      _info "[ldap] using local Helm chart archive ${helm_chart_ref}"
   fi

   local skip_repo_ops=0
   local is_oci_ref=0
   case "$helm_chart_ref" in
      /*|./*|../*|file://*)
         skip_repo_ops=1
         ;;
      oci://*)
         skip_repo_ops=1
         is_oci_ref=1
         ;;
   esac
   case "$helm_repo_url" in
      ""|/*|./*|../*|file://*)
         skip_repo_ops=1
         ;;
   esac

   if (( ! skip_repo_ops )); then
      _helm repo add "$helm_repo_name" "$helm_repo_url"
      if ! _helm --no-exit repo update "$helm_repo_name" >/dev/null 2>&1; then
         _warn "[ldap] failed to update Helm repo ${helm_repo_name}; provide LDAP_HELM_CHART_REF or LDAP_HELM_CHART_ARCHIVE pointing to a local chart when working offline."
      fi
   fi

   local values_template="$LDAP_CONFIG_DIR/values.yaml.tmpl"
   local values_rendered
   values_rendered=$(_ldap_render_template "$values_template" "ldap-values") || return 1

   if (( is_oci_ref )) && [[ -z "$version" ]]; then
      _err "[ldap] OCI charts require LDAP_HELM_CHART_VERSION. Set it to a published OpenLDAP chart version (e.g. 1.5.3) or point LDAP_HELM_CHART_ARCHIVE/LDAP_HELM_CHART_REF at a packaged chart."
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
            _err "[ldap] OCI chart ${helm_chart_ref} is unreachable. Pull it with 'helm pull ${helm_chart_ref} --version ${version_hint}' and reference the cached file (set LDAP_HELM_CHART_ARCHIVE to the resulting tgz), or ensure registry access is available."
         else
            _err "[ldap] chart reference ${helm_chart_ref} not found; set LDAP_HELM_CHART_ARCHIVE/LDAP_HELM_CHART_REF to a valid chart location."
         fi
         return 1
      fi
   fi

   local args=(upgrade --install "$release" "$helm_chart_ref" -n "$ns" -f "$values_rendered" --create-namespace)
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
         printf '%s\n' "$cm_yaml" | _kubectl apply -f - >/dev/null 2>&1 || \
            _warn "[ldap] unable to persist rendered values in ConfigMap openldap-values"
      else
         _warn "[ldap] rendered values file missing; skipping ConfigMap update"
      fi
   fi

   _cleanup_on_success "$values_rendered"
   return "$helm_rc"
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
   local admin_pass=""
   local config_pass=""
   local pod=""

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

   pod=$(_kubectl --no-exit -n "$ns" get pod -l "app.kubernetes.io/instance=${release},app.kubernetes.io/name=openldap-bitnami" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
   if [[ -z "$pod" ]]; then
      _warn "[ldap] unable to locate pod for release ${release} in namespace ${ns}; skipping admin password sync"
      return 1
   fi

   local sync_cmd
   read -r -d '' sync_cmd <<'EOS' || true
set -euo pipefail
export PATH="/opt/bitnami/openldap/bin:$PATH"
CONFIG_DN_VAR="${CONFIG_DN_OVERRIDE:-}"
if [[ -z "$CONFIG_DN_VAR" ]]; then
  CONFIG_DN_VAR="$(printenv LDAP_CONFIG_ADMIN_DN 2>/dev/null || true)"
fi
CONFIG_DN_VAR=${CONFIG_DN_VAR:-cn=admin,cn=config}
ADMIN_CN_VAR="${ADMIN_CN_OVERRIDE:-}"
if [[ -z "$ADMIN_CN_VAR" ]]; then
  ADMIN_CN_VAR="$(printenv LDAP_ADMIN_USERNAME 2>/dev/null || true)"
fi
ADMIN_CN_VAR=${ADMIN_CN_VAR:-ldap-admin}
ADMIN_DN_VAR="$ADMIN_DN"
SEARCH_DN=$(LDAPTLS_REQCERT=never ldapsearch -x -H ldap://127.0.0.1:1389 \
  -D "$CONFIG_DN_VAR" -w "$CONFIG_PASS" \
  -b "$BASE_DN" "(cn=${ADMIN_CN_VAR})" dn 2>/dev/null | awk 'tolower($1)=="dn:" {sub(/^dn:[[:space:]]*/,""); print; exit}')
if [[ -n "$SEARCH_DN" ]]; then
  ADMIN_DN_VAR="$SEARCH_DN"
fi
if command -v ldappasswd >/dev/null 2>&1; then
  LDAPTLS_REQCERT=never ldappasswd -x -H ldap://127.0.0.1:1389 \
    -D "$CONFIG_DN_VAR" -w "$CONFIG_PASS" \
    "$ADMIN_DN_VAR" -s "$ADMIN_PASS"
else
  LDAPTLS_REQCERT=never ldapmodify -x -H ldap://127.0.0.1:1389 \
    -D "$CONFIG_DN_VAR" -w "$CONFIG_PASS" <<EOF
dn: $ADMIN_DN_VAR
changetype: modify
replace: userPassword
userPassword: $ADMIN_PASS
EOF
fi

if ! LDAPTLS_REQCERT=never ldapwhoami -x -H ldap://127.0.0.1:1389 \
  -D "$ADMIN_DN_VAR" -w "$ADMIN_PASS" >/dev/null 2>&1; then
  printf 'VERIFY_FAIL:%s\n' "$ADMIN_DN_VAR"
  exit 2
fi

printf 'SYNC_OK:%s\n' "$ADMIN_DN_VAR"
EOS

   if [[ -z "$sync_cmd" ]]; then
      _warn "[ldap] unable to construct admin password sync script"
      return 1
   fi

   local sync_output=""
   if ! sync_output=$(printf '%s\n' "$sync_cmd" | _no_trace _kubectl --no-exit -n "$ns" exec "$pod" -- env ADMIN_DN="$admin_dn" ADMIN_PASS="$admin_pass" CONFIG_PASS="$config_pass" CONFIG_DN_OVERRIDE="${config_dn_override}" ADMIN_CN_OVERRIDE="$admin_user" BASE_DN="$base_dn" bash -s 2>&1); then
      sync_output=${sync_output//$'\r'/}
      if [[ "$sync_output" == *VERIFY_FAIL:* ]]; then
         local verified_dn="${sync_output##*VERIFY_FAIL:}"
         _warn "[ldap] unable to verify admin password for ${verified_dn}"
      else
         _warn "[ldap] unable to reconcile admin password (${sync_output})"
      fi
      return 1
   fi

   sync_output=${sync_output//$'\r'/}
   local reconciled_dn="$admin_dn"
   if [[ "$sync_output" == SYNC_OK:* ]]; then
      reconciled_dn="${sync_output#SYNC_OK:}"
   fi
   export LDAP_BINDDN="$reconciled_dn"
   _info "[ldap] reconciled admin password for ${reconciled_dn}"
   return 0
}

function deploy_ldap() {
   local restore_trace=0
   local namespace=""
   local release=""
   local chart_version=""

   case $- in
      *x*)
         restore_trace=1
         ;;
   esac

   while [[ $# -gt 0 ]]; do
      case "$1" in
         -h|--help)
            cat <<EOF
Usage: deploy_ldap [options] [namespace] [release] [chart-version]

Options:
  --namespace <ns>         Kubernetes namespace (default: ${LDAP_NAMESPACE})
  --release <name>         Helm release name (default: ${LDAP_RELEASE})
  --chart-version <ver>    Helm chart version (default: ${LDAP_HELM_CHART_VERSION:-<auto>})
  -h, --help               Show this help message

Positional overrides (kept for backwards compatibility):
  namespace                Equivalent to --namespace <ns>
  release                  Equivalent to --release <name>
  chart-version            Equivalent to --chart-version <ver>
EOF
            if (( restore_trace )); then
               set -x
            fi
            return 0
            ;;
         --namespace)
            if [[ -z "${2:-}" ]]; then
               _err "[ldap] --namespace flag requires an argument"
               return 1
            fi
            namespace="$2"
            shift 2
            continue
            ;;
         --namespace=*)
            namespace="${1#*=}"
            if [[ -z "$namespace" ]]; then
               _err "[ldap] --namespace flag requires a non-empty argument"
               return 1
            fi
            shift
            continue
            ;;
         --release)
            if [[ -z "${2:-}" ]]; then
               _err "[ldap] --release flag requires an argument"
               return 1
            fi
            release="$2"
            shift 2
            continue
            ;;
         --release=*)
            release="${1#*=}"
            if [[ -z "$release" ]]; then
               _err "[ldap] --release flag requires a non-empty argument"
               return 1
            fi
            shift
            continue
            ;;
         --chart-version)
            if [[ -z "${2:-}" ]]; then
               _err "[ldap] --chart-version flag requires an argument"
               return 1
            fi
            chart_version="$2"
            shift 2
            continue
            ;;
         --chart-version=*)
            chart_version="${1#*=}"
            if [[ -z "$chart_version" ]]; then
               _err "[ldap] --chart-version flag requires a non-empty argument"
               return 1
            fi
            shift
            continue
            ;;
         --)
            shift
            break
            ;;
         -*)
            _err "[ldap] unknown option: $1"
            return 1
            ;;
         *)
            if [[ -z "$namespace" ]]; then
               namespace="$1"
            elif [[ -z "$release" ]]; then
               release="$1"
            elif [[ -z "$chart_version" ]]; then
               chart_version="$1"
            else
               _err "[ldap] unexpected argument: $1"
               return 1
            fi
            ;;
      esac
      shift
   done

   if [[ -z "$namespace" ]]; then
      namespace="$LDAP_NAMESPACE"
   fi

   if [[ -z "$release" ]]; then
      release="$LDAP_RELEASE"
   fi

   if [[ -z "$chart_version" ]]; then
      chart_version="${LDAP_HELM_CHART_VERSION:-}"
   fi

   if (( restore_trace )); then
      set -x
   fi

   if [[ -z "$namespace" ]]; then
      _err "[ldap] namespace is required"
      return 1
   fi

   export LDAP_NAMESPACE="$namespace"
   export LDAP_RELEASE="$release"

   # ESO deployment managed by Jenkins plugin; skip redundant call
   # deploy_eso

   local vault_ns="${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}"
   local vault_release="${VAULT_RELEASE:-${VAULT_RELEASE_DEFAULT:-vault}}"

   # Check if Vault is sealed before attempting unseal
   if _vault_is_sealed "$vault_ns" "$vault_release"; then
      # Vault is sealed - attempt to unseal it
      _info "[ldap] Vault ${vault_ns}/${vault_release} is sealed; attempting to unseal"
      if ! _vault_replay_cached_unseal "$vault_ns" "$vault_release"; then
         _err "[ldap] Vault ${vault_ns}/${vault_release} is sealed and cannot be unsealed; LDAP deployment requires accessible Vault"
      fi
   else
      local seal_check_rc=$?
      if (( seal_check_rc == 1 )); then
         # Vault is unsealed - continue normally
         _info "[ldap] Vault ${vault_ns}/${vault_release} is already unsealed"
      elif (( seal_check_rc == 2 )); then
         # Cannot determine seal status - attempt unseal anyway as fallback
         _warn "[ldap] Unable to determine Vault seal status; attempting unseal as fallback"
         if ! _vault_replay_cached_unseal "$vault_ns" "$vault_release"; then
            _err "[ldap] Cannot access Vault ${vault_ns}/${vault_release}; LDAP deployment requires accessible Vault"
         fi
      fi
   fi

   if ! _ldap_seed_admin_secret; then
      return 1
   fi

   if ! _ldap_seed_ldif_secret; then
      return 1
   fi

   if ! _vault_configure_secret_reader_role \
         "$vault_ns" \
         "$vault_release" \
         "$LDAP_ESO_SERVICE_ACCOUNT" \
         "$namespace" \
         "$LDAP_VAULT_KV_MOUNT" \
         "$LDAP_VAULT_POLICY_PREFIX" \
         "$LDAP_ESO_ROLE"; then
      _err "[ldap] failed to configure Vault role ${LDAP_ESO_ROLE} for namespace ${namespace}"
      return 1
   fi

   _ldap_ensure_namespace "$namespace" || return 1

   if ! _ldap_apply_eso_resources "$namespace"; then
      _err "[ldap] failed to apply ESO manifests for namespace ${namespace}"
      return 1
   fi

   if ! _ldap_wait_for_secret "$namespace" "${LDAP_ADMIN_SECRET_NAME}"; then
      _err "[ldap] Vault-sourced secret ${LDAP_ADMIN_SECRET_NAME} not available"
      return 1
   fi

   if [[ "${LDAP_LDIF_ENABLED:-false}" == "true" && -n "${LDAP_LDIF_VAULT_PATH:-}" ]]; then
      if ! _ldap_wait_for_secret "$namespace" "${LDAP_LDIF_SECRET_NAME}"; then
         _err "[ldap] Vault-sourced LDIF secret ${LDAP_LDIF_SECRET_NAME} not available"
         return 1
      fi
   fi

   local deploy_rc=0
   if ! _ldap_deploy_chart "$namespace" "$release" "$chart_version"; then
      deploy_rc=$?
   fi

   if (( deploy_rc == 0 )); then
      local deploy_name="${release}-openldap-bitnami"
      if ! _kubectl --no-exit -n "$namespace" rollout status "deployment/${deploy_name}" --timeout=180s; then
         _warn "[ldap] deployment ${namespace}/${deploy_name} not ready; skipping smoke test"
         return "$deploy_rc"
      fi

      if ! _ldap_sync_admin_password "$namespace" "$release"; then
         _warn "[ldap] admin password sync failed; continuing with smoke test"
      fi

      local smoke_script="${SCRIPT_DIR}/tests/plugins/openldap.sh"
      local service_name="${LDAP_SERVICE_NAME:-${release}-openldap-bitnami}"
      local smoke_port="${LDAP_SMOKE_PORT:-3389}"
      if [[ -x "$smoke_script" ]]; then
         "$smoke_script" "$namespace" "$release" "$service_name" "$smoke_port" "$LDAP_BASE_DN" || \
            _warn "[ldap] smoke test failed; inspect output above"
      elif [[ -r "$smoke_script" ]]; then
         bash "$smoke_script" "$namespace" "$release" "$service_name" "$smoke_port" "$LDAP_BASE_DN" || \
            _warn "[ldap] smoke test failed; inspect output above"
      else
         _warn "[ldap] smoke test helper missing at ${smoke_script}; skipping verification"
      fi
   fi

   return "$deploy_rc"
}
