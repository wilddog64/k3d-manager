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

   if _helm "${args[@]}"; then
      _cleanup_on_success "$values_rendered"
      return 0
   fi
   return 1
}

function deploy_ldap() {
   local restore_trace=0
   local namespace=""
   local release=""
   local chart_version=""

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
            echo "Usage: deploy_ldap [namespace=${LDAP_NAMESPACE}] [release=${LDAP_RELEASE}] [chart-version=${LDAP_HELM_CHART_VERSION:-<auto>}]"
            return 0
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
