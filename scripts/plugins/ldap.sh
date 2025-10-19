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

function _ldap_set_sensitive_var() {
   local name="${1:?variable name required}"
   local value="${2:-}"
   local wasx=0
   case $- in *x*) wasx=1; set +x;; esac
   printf -v "$name" '%s' "$value"
   if (( wasx )); then
      set -x
   fi
}

function _ldap_write_sensitive_file() {
   local path="${1:?path required}"
   local data="${2:-}"
   local wasx=0
   local old_umask
   case $- in *x*) wasx=1; set +x;; esac
   old_umask=$(umask)
   umask 077
   printf '%s' "$data" > "$path"
   chmod 600 "$path" 2>/dev/null || true
   umask "$old_umask"
   if (( wasx )); then
      set -x
   fi
}

function _ldap_remove_sensitive_file() {
   local path="${1:-}"
   local wasx=0
   if [[ -z "$path" ]]; then
      return 0
   fi
   case $- in *x*) wasx=1; set +x;; esac
   rm -f -- "$path"
   if (( wasx )); then
      set -x
   fi
}

function _ldap_build_credential_blob() {
   local username="${1:?username required}"
   local password="${2:?password required}"
   local blob=""
   local wasx=0
   case $- in *x*) wasx=1; set +x;; esac
   printf -v blob 'username=%s\npassword=%s\n' "$username" "$password"
   if (( wasx )); then
      set -x
   fi
   printf '%s' "$blob"
}

function _ldap_parse_credential_blob() {
   local blob="${1:-}"
   local username=""
   local password=""
   local line key value

   if [[ -z "$blob" ]]; then
      return 1
   fi

   while IFS='=' read -r key value; do
      case "$key" in
         username) username="$value" ;;
         password) password="$value" ;;
      esac
   done <<<"$blob"

   if [[ -z "$username" || -z "$password" ]]; then
      return 1
   fi

   _ldap_set_sensitive_var LDAP_HELM_REGISTRY_USERNAME "$username"
   _ldap_set_sensitive_var LDAP_HELM_REGISTRY_PASSWORD "$password"
   return 0
}

function _ldap_chart_registry_host() {
   local ref="${1:-}"
   if [[ "$ref" == oci://* ]]; then
      ref="${ref#oci://}"
      printf '%s\n' "${ref%%/*}"
      return 0
   fi
   return 1
}

function _ldap_secret_tool_ready() {
   if _command_exist secret-tool; then
      return 0
   fi

   if _is_linux; then
      if _ensure_secret_tool >/dev/null 2>&1; then
         return 0
      fi
   fi

   return 1
}

function _ldap_store_registry_credentials() {
   local host="${1:?registry host required}"
   local username="${2:?username required}"
   local password="${3:?password required}"
   local blob=""
   local blob_file=""

   blob=$(_ldap_build_credential_blob "$username" "$password") || return 1
   blob_file=$(mktemp -t ldap-registry-cred.XXXXXX) || return 1
   _ldap_write_sensitive_file "$blob_file" "$blob"

   if _is_mac; then
      local service="k3d-manager-ldap:${host}"
      local account="k3d-manager-ldap"
      local rc=0
      _no_trace bash -c 'security delete-generic-password -s "$1" >/dev/null 2>&1 || true' _ "$service" >/dev/null 2>&1
      if ! _no_trace bash -c 'security add-generic-password -s "$1" -a "$2" -w "$3" >/dev/null' _ "$service" "$account" "$blob"; then
         rc=$?
      fi
      _ldap_remove_sensitive_file "$blob_file"
      return $rc
   fi

   if _ldap_secret_tool_ready; then
      local label="k3d-manager LDAP registry ${host}"
      local rc=0
      _no_trace bash -c 'secret-tool clear service "$1" registry "$2" type "$3" >/dev/null 2>&1 || true' _ "k3d-manager-ldap" "$host" "helm-oci" >/dev/null 2>&1
      local store_output=""
      if ! store_output=$(_no_trace bash -c 'secret-tool store --label "$1" service "$2" registry "$3" type "$4" < "$5"' _ "$label" "k3d-manager-ldap" "$host" "helm-oci" "$blob_file" 2>&1); then
         rc=$?
         if [[ -n "$store_output" ]]; then
            _warn "[ldap] secret-tool store failed for ${host}: ${store_output}"
         fi
      fi
      _ldap_remove_sensitive_file "$blob_file"
      return $rc
   fi

   _ldap_remove_sensitive_file "$blob_file"
   return 1
}

function _ldap_load_registry_credentials() {
   local host="${1:?registry host required}"
   local blob=""

   if _is_mac; then
      local service="k3d-manager-ldap:${host}"
      blob=$(_no_trace bash -c 'security find-generic-password -s "$1" -w' _ "$service" 2>/dev/null || true)
   elif _command_exist secret-tool; then
      blob=$(_no_trace bash -c 'secret-tool lookup service "$1" registry "$2" type "$3"' _ "k3d-manager-ldap" "$host" "helm-oci" 2>/dev/null || true)
   fi

   if [[ -z "$blob" ]]; then
      return 1
   fi

   _ldap_parse_credential_blob "$blob" || return 1
   return 0
}

function _ldap_json_escape() {
   local value="${1:-}"
   value="${value//\\/\\\\}"
   value="${value//\"/\\\"}"
   printf '%s' "$value"
}

function _ldap_write_helm_registry_config() {
   local host="${1:?registry host required}"
   local username="${2:?username required}"
   local password="${3:?password required}"
   local destination="${4:?destination path required}"

   local wasx=0
   case $- in *x*) wasx=1; set +x;; esac
   local auth=""
   auth=$(printf '%s:%s' "$username" "$password" | base64 | tr -d $'\r\n')

   local esc_user esc_pass
   esc_user=$(_ldap_json_escape "$username")
   esc_pass=$(_ldap_json_escape "$password")

   local config=""
   config+=$'{\n  "auths": {\n'
   config+="    \"${host}\": {\n"
   config+="      \"username\": \"${esc_user}\",\n"
   config+="      \"password\": \"${esc_pass}\",\n"
   config+="      \"auth\": \"${auth}\"\n"
   config+="    }"

   if [[ "$host" == "registry-1.docker.io" ]]; then
      config+=$',\n    "https://index.docker.io/v1/": {\n'
      config+="      \"username\": \"${esc_user}\",\n"
      config+="      \"password\": \"${esc_pass}\",\n"
      config+="      \"auth\": \"${auth}\"\n"
      config+="    }\n"
   else
      config+=$'\n'
   fi

   config+=$'  }\n}\n'

   _ldap_write_sensitive_file "$destination" "$config"
   local rc=$?
   if (( wasx )); then
      set -x
   fi
   return $rc
}

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

function _ldap_fetch_chart_archive() {
   local chart_ref="${1:?chart reference required}"
   local version="${2:?chart version required}"
   local destination="${3:?destination path required}"

   local destination_dir
   destination_dir="$(dirname "$destination")"
   if ! mkdir -p "$destination_dir"; then
      _err "[ldap] failed to create directory for chart cache: ${destination_dir}"
      return 1
   fi

   local registry_host=""
   local registry_config_file=""
   if [[ "$chart_ref" == oci://* ]]; then
      registry_host="${chart_ref#oci://}"
      registry_host="${registry_host%%/*}"

      if [[ -z "${LDAP_HELM_REGISTRY_USERNAME:-}" || -z "${LDAP_HELM_REGISTRY_PASSWORD:-}" ]]; then
         _ldap_load_registry_credentials "$registry_host" >/dev/null 2>&1 || true
      fi

      if [[ -n "${LDAP_HELM_REGISTRY_USERNAME:-}" && -n "${LDAP_HELM_REGISTRY_PASSWORD:-}" ]]; then
         registry_config_file=$(mktemp -t ldap-helm-registry.XXXXXX.json) || return 1
         if _ldap_write_helm_registry_config "$registry_host" "${LDAP_HELM_REGISTRY_USERNAME}" "${LDAP_HELM_REGISTRY_PASSWORD}" "$registry_config_file"; then
            _info "[ldap] prepared temporary Helm registry config for ${registry_host}"
         else
            _warn "[ldap] unable to prepare Helm registry config for ${registry_host}; attempting anonymous pull."
            _ldap_remove_sensitive_file "$registry_config_file"
            registry_config_file=""
         fi
      elif [[ -n "${LDAP_HELM_REGISTRY_USERNAME:-}" || -n "${LDAP_HELM_REGISTRY_PASSWORD:-}" ]]; then
         _warn "[ldap] partial OCI credentials detected for ${registry_host}; supply both username and password for authenticated pulls."
      fi
   fi

   local download_dir
   download_dir="$(mktemp -d 2>/dev/null || mktemp -d -t ldap-helm-chart.XXXXXX)" || return 1
   local pulled_chart=""
   local pull_output=""
   local helm_env_cmd=()
   local pull_rc=0

   if [[ -n "$registry_config_file" ]]; then
      helm_env_cmd=(HELM_REGISTRY_CONFIG="$registry_config_file")
   fi

   if [[ -n "$registry_config_file" ]]; then
      pull_output=$(HELM_REGISTRY_CONFIG="$registry_config_file" _helm pull "$chart_ref" --version "$version" --destination "$download_dir" 2>&1) || pull_rc=$?
   else
      pull_output=$(_helm pull "$chart_ref" --version "$version" --destination "$download_dir" 2>&1) || pull_rc=$?
   fi

   _ldap_remove_sensitive_file "$registry_config_file"

   if (( pull_rc != 0 )); then
      if [[ "$pull_output" == *"unauthorized"* || "$pull_output" == *"authentication required"* ]]; then
         if [[ -n "$registry_host" ]]; then
            _err "[ldap] failed to pull ${chart_ref} (HTTP 401). Re-run with deploy_ldap --username/--password or refresh stored credentials for ${registry_host}."
         else
            _err "[ldap] failed to pull chart ${chart_ref}: authentication required."
         fi
      else
         _err "[ldap] failed to pull chart ${chart_ref}: ${pull_output}"
      fi
      _cleanup_on_success "$download_dir"
      return 1
   fi

   pulled_chart=$(find "$download_dir" -maxdepth 1 -type f -name '*.tgz' | head -n 1 || true)
   if [[ -z "$pulled_chart" ]]; then
      _cleanup_on_success "$download_dir"
      _err "[ldap] unable to locate pulled Helm chart archive for ${chart_ref}"
      return 1
   fi

   if ! mv -f "$pulled_chart" "$destination"; then
      _cleanup_on_success "$download_dir"
      _err "[ldap] failed to move Helm chart archive into ${destination}"
      return 1
   fi

   _cleanup_on_success "$download_dir"
   _info "[ldap] cached Helm chart archive at ${destination}"
   return 0
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

   api_version=$(_ldap_detect_eso_api_version) || api_version="$default_version"
   _info "[ldap] using ESO API version ${api_version}"
   export LDAP_ESO_API_VERSION="$api_version"
   rendered=$(_ldap_render_template "$tmpl" "ldap-eso") || return 1
   if _kubectl apply -f "$rendered"; then
      _cleanup_on_success "$rendered"
      return 0
   fi
   return 1
}

function _ldap_deploy_chart() {
   local ns="${1:-$LDAP_NAMESPACE}"
   local release="${2:-$LDAP_RELEASE}"
   local version="${3:-${LDAP_HELM_CHART_VERSION:-}}"

   local helm_repo_name_default="bitnami"
   local helm_repo_name="${LDAP_HELM_REPO_NAME:-$helm_repo_name_default}"
   local helm_repo_url_default="https://charts.bitnami.com/bitnami"
   local helm_repo_url="${LDAP_HELM_REPO_URL:-$helm_repo_url_default}"
   local helm_chart_ref_default="oci://registry-1.docker.io/bitnamicharts/openldap"
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
   elif [[ "$helm_chart_ref" == oci://* && -n "$chart_archive_candidate" && -n "$version" ]]; then
      _info "[ldap] attempting to pull ${helm_chart_ref} (version ${version}) for local caching"
      if _ldap_fetch_chart_archive "$helm_chart_ref" "$version" "$chart_archive_candidate"; then
         chart_archive="$chart_archive_candidate"
      else
         _err "[ldap] failed to pull OCI chart ${helm_chart_ref}. Download it manually with 'helm pull ${helm_chart_ref} --version ${version}' and set LDAP_HELM_CHART_ARCHIVE to the resulting file."
         return 1
      fi
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
         _warn "[ldap] failed to update Helm repo ${helm_repo_name}; offline or airgapped environments must provide LDAP_HELM_CHART_REF or LDAP_HELM_CHART_ARCHIVE pointing to a local chart."
      fi
   fi

   local values_template="$LDAP_CONFIG_DIR/values.yaml.tmpl"
   local values_rendered
   values_rendered=$(_ldap_render_template "$values_template" "ldap-values") || return 1

   if (( is_oci_ref )) && [[ -z "$version" ]]; then
      _err "[ldap] OCI charts require LDAP_HELM_CHART_VERSION. Set it to a published OpenLDAP chart version (e.g. 13.2.3) or point LDAP_HELM_CHART_ARCHIVE/LDAP_HELM_CHART_REF at a packaged chart."
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

   if _helm "${args[@]}"; then
      _cleanup_on_success "$values_rendered"
      return 0
   fi
   return 1
}

function deploy_ldap() {
   local username_override=""
   local password_override=""
   local store_credentials=0
   local restore_trace=0

   case $- in
      *x*)
         restore_trace=1
         set +x
         ;;
   esac

   while [[ $# -gt 0 ]]; do
      case "$1" in
         -h|--help)
            if (( restore_trace )); then
               set -x
            fi
            echo "Usage: deploy_ldap [--username <registry-user>] [--password <registry-pass>] [namespace=${LDAP_NAMESPACE}] [release=${LDAP_RELEASE}] [chart-version=${LDAP_HELM_CHART_VERSION:-<auto>}]"
            echo "Credentials can also be supplied via LDAP_HELM_REGISTRY_USERNAME and LDAP_HELM_REGISTRY_PASSWORD."
            return 0
            ;;
         --username)
            if [[ -z "${2:-}" ]]; then
               _err "[ldap] --username flag requires an argument"
               return 1
            fi
            username_override="$2"
            store_credentials=1
            shift 2
            continue
            ;;
         --username=*)
            username_override="${1#*=}"
            if [[ -z "$username_override" ]]; then
               _err "[ldap] --username flag requires a non-empty argument"
               return 1
            fi
            store_credentials=1
            shift
            continue
            ;;
         --password)
            if [[ -z "${2:-}" ]]; then
               _err "[ldap] --password flag requires an argument"
               return 1
            fi
            password_override="$2"
            store_credentials=1
            shift 2
            continue
            ;;
         --password=*)
            password_override="${1#*=}"
            if [[ -z "$password_override" ]]; then
               _err "[ldap] --password flag requires a non-empty argument"
               return 1
            fi
            store_credentials=1
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
            break
            ;;
      esac
   done

   if [[ -n "$username_override" ]]; then
      _ldap_set_sensitive_var LDAP_HELM_REGISTRY_USERNAME "$username_override"
      store_credentials=1
   fi
   if [[ -n "$password_override" ]]; then
      _ldap_set_sensitive_var LDAP_HELM_REGISTRY_PASSWORD "$password_override"
      store_credentials=1
   fi

   local registry_host=""
   registry_host=$(_ldap_chart_registry_host "${LDAP_HELM_CHART_REF:-}") || registry_host=""

   if [[ -n "$registry_host" ]]; then
      if [[ -z "${LDAP_HELM_REGISTRY_USERNAME:-}" || -z "${LDAP_HELM_REGISTRY_PASSWORD:-}" ]]; then
         _ldap_load_registry_credentials "$registry_host" >/dev/null 2>&1 || true
      fi

      if (( store_credentials )) && [[ -n "${LDAP_HELM_REGISTRY_USERNAME:-}" && -n "${LDAP_HELM_REGISTRY_PASSWORD:-}" ]]; then
         if _ldap_store_registry_credentials "$registry_host" "${LDAP_HELM_REGISTRY_USERNAME}" "${LDAP_HELM_REGISTRY_PASSWORD}"; then
            _info "[ldap] stored OCI registry credentials"
         else
            _warn "[ldap] unable to persist OCI registry credentials; continuing with current values."
         fi
      fi
   fi

   local namespace=""
   local release=""
   local chart_version=""

   if [[ $# -gt 0 ]]; then
      namespace="$1"
      shift
   else
      namespace="$LDAP_NAMESPACE"
   fi

   if [[ $# -gt 0 ]]; then
      release="$1"
      shift
   else
      release="$LDAP_RELEASE"
   fi

   if [[ $# -gt 0 ]]; then
      chart_version="$1"
      shift
   else
      chart_version="${LDAP_HELM_CHART_VERSION:-}"
   fi

   if [[ $# -gt 0 ]]; then
      _err "[ldap] unexpected argument: $1"
      return 1
   fi

   if [[ -z "$namespace" ]]; then
      _err "[ldap] namespace is required"
      return 1
   fi

   export LDAP_NAMESPACE="$namespace"
   export LDAP_RELEASE="$release"

   deploy_eso

   _ldap_ensure_namespace "$namespace" || return 1

   if ! _ldap_apply_eso_resources "$namespace"; then
      _err "[ldap] failed to apply ESO manifests for namespace ${namespace}"
      return 1
   fi

   local deploy_rc=0
   if ! _ldap_deploy_chart "$namespace" "$release" "$chart_version"; then
      deploy_rc=$?
   fi

   if (( restore_trace )); then
      set -x
   fi

   return "$deploy_rc"
}
