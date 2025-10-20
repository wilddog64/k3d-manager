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

   local full_path="${mount}/${vault_path}"

   if _vault_exec --no-exit "$vault_ns" "vault kv get ${full_path}" "$vault_release" >/dev/null 2>&1; then
      _info "[ldap] Vault secret ${full_path} already exists; skipping seed"
      return 0
   fi

   if ! _vault_exec --no-exit "$vault_ns" "vault status >/dev/null 2>&1" "$vault_release"; then
      _err "[ldap] Vault instance ${vault_ns}/${vault_release} unavailable or sealed; unseal before deploy"
   fi

   local admin_password=""
   local config_password=""
   admin_password=$(_no_trace bash -c 'openssl rand -base64 24 | tr -d "\n"')
   if [[ -z "$admin_password" ]]; then
      _err "[ldap] failed to generate admin password"
      return 1
   fi

   config_password=$(_no_trace bash -c 'openssl rand -base64 24 | tr -d "\n"')
   if [[ -z "$config_password" ]]; then
      _err "[ldap] failed to generate config password"
      return 1
   fi

   local script payload
   printf -v payload '{ "%s": "%s", "%s": "%s", "%s": "%s" }' \
      "$username_key" "$username" "$password_key" "$admin_password" "$config_key" "$config_password"

   printf -v script "cat <<'EOF' | vault kv put %s -\n%s\nEOF" \
      "$full_path" "$payload"

   if _vault_exec --no-exit "$vault_ns" "$script" "$vault_release"; then
      _info "[ldap] seeded Vault secret ${full_path}"
      return 0
   fi

   _err "[ldap] unable to seed Vault admin secret ${full_path}"
   return 1
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

   deploy_eso

   local vault_ns="${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}"
   local vault_release="${VAULT_RELEASE:-${VAULT_RELEASE_DEFAULT:-vault}}"
   if ! _vault_replay_cached_unseal "$vault_ns" "$vault_release"; then
      _warn "[ldap] unable to auto-unseal Vault ${vault_ns}/${vault_release}; continuing"
   fi

   if ! _ldap_seed_admin_secret; then
      return 1
   fi

   if ! _vault_configure_secret_reader_role \
         "$vault_ns" \
         "$vault_release" \
         "$LDAP_ESO_SERVICE_ACCOUNT" \
         "$namespace" \
         "$LDAP_VAULT_KV_MOUNT" \
         "$LDAP_ADMIN_VAULT_PATH" \
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

      local smoke_script="${SCRIPT_DIR}/tests/test-openldap.sh"
      local service_name="${LDAP_SERVICE_NAME:-${release}-openldap-bitnami}"
      local smoke_port="${LDAP_SMOKE_PORT:-3389}"
      if [[ -x "$smoke_script" ]]; then
         if ! "$smoke_script" "$namespace" "$release" "$service_name" "$smoke_port" "$LDAP_BASE_DN"; then
            _warn "[ldap] smoke test failed; inspect output above"
         fi
      else
         _warn "[ldap] smoke test helper missing at ${smoke_script}; skipping verification"
      fi
   fi

   return "$deploy_rc"
}
