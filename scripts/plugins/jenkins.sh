# shellcheck disable=SC1090,SC2034,SC2155,SC2016,SC2329

VAULT_PLUGIN="$PLUGINS_DIR/vault.sh"
if [[ -r "$VAULT_PLUGIN" ]]; then
   # shellcheck disable=SC1090
   source "$VAULT_PLUGIN"
fi

# Source secret backend abstraction (optional, for new abstraction layer)
if [[ -n "${SCRIPT_DIR:-}" ]]; then
   SECRET_BACKEND_LIB="$SCRIPT_DIR/lib/secret_backend.sh"
   if [[ -r "$SECRET_BACKEND_LIB" ]]; then
      # shellcheck disable=SC1090
      source "$SECRET_BACKEND_LIB"
   fi
fi

# Source directory service abstraction (optional, for new abstraction layer)
if [[ -n "${SCRIPT_DIR:-}" ]]; then
   DIRECTORY_SERVICE_LIB="$SCRIPT_DIR/lib/directory_service.sh"
   if [[ -r "$DIRECTORY_SERVICE_LIB" ]]; then
      # shellcheck disable=SC1090
      source "$DIRECTORY_SERVICE_LIB"
   fi
fi

# Ensure _no_trace is defined
command -v _no_trace >/dev/null 2>&1 || _no_trace() { "$@"; }

if ! declare -f _vault_issue_pki_tls_secret >/dev/null 2>&1; then
   _vault_issue_pki_tls_secret() { :; }
fi
export -f _vault_issue_pki_tls_secret 2>/dev/null || true

JENKINS_CONFIG_DIR="$SCRIPT_DIR/etc/jenkins"
JENKINS_VARS_FILE="$JENKINS_CONFIG_DIR/vars.sh"

if [[ ! -r "$JENKINS_VARS_FILE" ]]; then
   _err "Jenkins vars file not found: $JENKINS_VARS_FILE"
fi
# shellcheck disable=SC1090
source "$JENKINS_VARS_FILE"

function _jenkins_hostpath_dir() {
   printf '%s\n' "${JENKINS_HOME_PATH:-${SCRIPT_DIR}/storage/jenkins_home}"
}

function _jenkins_node_has_mount() {
   local _node="${1:-}"
   local host_dir="${2:-}"
   if [[ -z "$_node" || -z "$host_dir" ]]; then
      return 1
   fi
   [[ -d "$host_dir" ]]
}

function _jenkins_resolve_cluster_name() {
   local provided="${1:-${CLUSTER_NAME:-}}"
   if [[ -n "$provided" ]]; then
      printf '%s\n' "$provided"
      return 0
   fi

   if ! declare -f _k3d >/dev/null 2>&1; then
      return 1
   fi

   local cluster_list=""
   if ! cluster_list=$(_k3d cluster list 2>/dev/null); then
      return 1
   fi

   local detected=""
   detected=$(printf '%s\n' "$cluster_list" | awk 'NR>1 && NF {print $1; exit}')
   if [[ -z "$detected" || "$detected" == "NAME" ]]; then
      return 1
   fi

   printf '%s\n' "$detected"
}

function _jenkins_require_hostpath_mounts() {
   local cluster="${1:-}"
   local host_dir
   JENKINS_MISSING_HOSTPATH_NODES=""

   host_dir=$(_jenkins_hostpath_dir)
   mkdir -p "$host_dir"

   if [[ -z "$cluster" ]]; then
      if cluster=$(_jenkins_resolve_cluster_name); then
         :
      else
         _warn "[jenkins] unable to determine k3d cluster name; skipping hostPath mount validation"
         return 0
      fi
   fi

   if ! declare -f _k3d >/dev/null 2>&1; then
      _warn "[jenkins] k3d CLI helper not available; skipping hostPath mount validation"
      return 0
   fi

   local node_output=""
   node_output=$(_k3d node list 2>/dev/null || true)
   if [[ -z "$node_output" ]]; then
      _warn "[jenkins] unable to list k3d nodes; skipping hostPath mount validation"
      return 0
   fi

   local -a missing_nodes=()
   while read -r name role cluster_name status _rest; do
      [[ -z "$name" ]] && continue
      [[ "$name" =~ ^NAME$ ]] && continue
      if [[ "$cluster_name" != "$cluster" ]]; then
         continue
      fi
      if ! _jenkins_node_has_mount "$name" "$host_dir"; then
         missing_nodes+=("$name")
      fi
   done <<< "$node_output"

   if (( ${#missing_nodes[@]} )); then
      JENKINS_MISSING_HOSTPATH_NODES="${missing_nodes[*]}"
      echo "[jenkins] hostPath mount ${host_dir} missing from nodes: ${missing_nodes[*]}. Update your cluster configuration via create_cluster." >&2
      return 1
   fi

   return 0
}

declare -a _JENKINS_RENDERED_MANIFESTS=()
declare -a _JENKINS_DEDUP_TRAP_ARGS=()
declare -a _JENKINS_SMOKE_CMD=()
declare -a _JENKINS_SMOKE_ENV=()
declare _JENKINS_TEMPLATE_FILE=""
declare _JENKINS_AUTH_MODE=""
declare _JENKINS_VAULT_PREFIX_ARG=""
_JENKINS_PREV_EXIT_TRAP_CMD=""
_JENKINS_PREV_EXIT_TRAP_HANDLER=""
_JENKINS_PREV_RETURN_TRAP_CMD=""
_JENKINS_PREV_RETURN_TRAP_HANDLER=""

function _jenkins_render_template() {
   local template="${1:?template path required}"
   local prefix="${2:-jenkins}"

   if [[ ! -r "$template" ]]; then
      _err "[jenkins] template not found: $template"
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

function _jenkins_apply_eso_resources() {
   local ns="${1:-$JENKINS_NAMESPACE}"
   local tmpl="$JENKINS_CONFIG_DIR/eso.yaml"
   local rendered
   local final_manifest
   local apply_rc=0

   if [[ ! -r "$tmpl" ]]; then
      _err "[jenkins] ESO template not found: $tmpl"
      return 1
   fi

   export JENKINS_ESO_API_VERSION="${JENKINS_ESO_API_VERSION:-external-secrets.io/v1}"
   rendered=$(_jenkins_render_template "$tmpl" "jenkins-eso") || return 1

   # If LDAP is disabled, remove the jenkins-ldap-config ExternalSecret from the manifest
   if (( ! JENKINS_LDAP_ENABLED )); then
      final_manifest=$(mktemp -t "jenkins-eso-filtered.XXXXXX.yaml") || {
         _cleanup_on_success "$rendered"
         return 1
      }

      # Filter out the LDAP ExternalSecret section
      # This uses awk to remove the YAML document containing the LDAP secret
      awk -v ldap_secret="$JENKINS_LDAP_SECRET_NAME" '
         BEGIN { in_doc=0; in_ldap=0; doc_buffer=""; line_count=0 }
         /^---$/ {
            # End of previous document - print if not LDAP
            if (in_doc && !in_ldap && doc_buffer != "") {
               print doc_buffer
            }
            # Start new document
            in_doc=1
            in_ldap=0
            doc_buffer="---"
            line_count=0
            next
         }
         in_doc {
            line_count++
            doc_buffer = doc_buffer "\n" $0
            # Check if this document is the LDAP ExternalSecret
            if (!in_ldap && /^  name: / && $0 ~ ldap_secret) {
               in_ldap=1
            }
         }
         !in_doc {
            print
         }
         END {
            # Print last document if not LDAP
            if (in_doc && !in_ldap && doc_buffer != "") {
               print doc_buffer
            }
         }
      ' "$rendered" > "$final_manifest"

      _cleanup_on_success "$rendered"
      rendered="$final_manifest"
   fi

   if ! _kubectl apply -f "$rendered"; then
      apply_rc=$?
   fi
   _cleanup_on_success "$rendered"
   return "$apply_rc"
}

function _jenkins_wait_for_secret() {
   local ns="${1:-$JENKINS_NAMESPACE}"
   local secret="${2:-$JENKINS_ADMIN_SECRET_NAME}"
   local timeout="${3:-60}"
   local interval=3
   local elapsed=0

   if [[ -z "$secret" ]]; then
      _err "[jenkins] secret name required for wait"
      return 1
   fi

   _info "[jenkins] waiting for secret ${ns}/${secret}"
   while (( elapsed < timeout )); do
      if _kubectl --no-exit -n "$ns" get secret "$secret" >/dev/null 2>&1; then
         _info "[jenkins] secret ${ns}/${secret} available"
         return 0
      fi
      sleep "$interval"
      elapsed=$(( elapsed + interval ))
   done

   _err "[jenkins] timed out waiting for secret ${ns}/${secret}"
}

function _jenkins_capture_trap_state() {
   local signal="$1"
   local cmd_var="$2"
   local handler_var="$3"
   local trap_output quoted_handler handler=""

   trap_output=$(trap -p "$signal")
   if [[ -z "$trap_output" ]]; then
      printf -v "$cmd_var" '%s' ""
      printf -v "$handler_var" '%s' ""
      return
   fi

   quoted_handler=${trap_output#trap -- }
   quoted_handler="${quoted_handler% "$signal"}"
   if [[ -n "$quoted_handler" ]]; then
      local handler_literal
      if [[ ${quoted_handler} == "'"*"'" ]]; then
         if (( ${#quoted_handler} >= 2 )); then
            handler_literal=${quoted_handler:1:${#quoted_handler}-2}
            handler_literal=${handler_literal//\'\\\'\'/\'}
         else
            handler_literal=""
         fi
      else
         handler_literal=$quoted_handler
      fi
      local literal_var="_JENKINS_PREV_${signal}_TRAP_LITERAL"
      printf -v "$literal_var" '%s' "$handler_literal"
      local -a handler_args=()
      eval "handler_args=( ${handler_literal} )"
      if (( ${#handler_args[@]} )); then
         local handler_command
         printf -v handler_command '%q ' "${handler_args[@]}"
         handler_command=${handler_command% }
         handler="$handler_command"
      fi
   fi

   printf -v "$cmd_var" '%s' "$trap_output"
   printf -v "$handler_var" '%s' "$handler"
}

# _jenkins_deduplicate_trap_tokens
# Deduplicates trap args relative to saved handler tokens.
# Sets global: _JENKINS_DEDUP_TRAP_ARGS
function _jenkins_deduplicate_trap_tokens() {
   local handler_var="$1"
   shift || true
   local -a trap_args=("$@")
   local -a saved_tokens=()

   [[ -n "${!handler_var:-}" ]] && eval "saved_tokens=( ${!handler_var} )"

   local skip_count=0
   (( ${#saved_tokens[@]} > 1 )) && skip_count=$(( ${#saved_tokens[@]} - 1 ))

   if (( skip_count > 0 )); then
      trap_args=("${trap_args[@]:${skip_count}}")
   else
      while (( ${#trap_args[@]} )); do
         case "${trap_args[0]}" in
            EXIT|RETURN|TERM|INT|HUP|_JENKINS_PREV_*)
               trap_args=("${trap_args[@]:1}")
               ;;
            *)
               break
               ;;
         esac
      done

      if (( ${#trap_args[@]} )); then
         local -a filtered=()
         local token discard=1
         for token in "${trap_args[@]}"; do
            case "$token" in
               EXIT|RETURN|TERM|INT|HUP|_JENKINS_PREV_*) ;;
               *) discard=0; break ;;
            esac
         done
         if (( discard == 0 )); then
            for token in "${trap_args[@]}"; do
               case "$token" in
                  EXIT|RETURN|TERM|INT|HUP|_JENKINS_PREV_*) ;;
                  *) filtered+=("$token") ;;
               esac
            done
            trap_args=("${filtered[@]}")
         else
            trap_args=()
         fi
      fi
   fi

   if (( ${#trap_args[@]} )); then
      local total=${#trap_args[@]}
      if (( total % 2 == 0 )); then
         local half=$(( total / 2 ))
         local duplicate=1 i
         for (( i=0; i<half; i++ )); do
            if [[ "${trap_args[i]}" != "${trap_args[i+half]}" ]]; then
               duplicate=0
               break
            fi
         done
         if (( duplicate )); then
            trap_args=("${trap_args[@]:0:half}")
         fi
      fi
   fi

   _JENKINS_DEDUP_TRAP_ARGS=("${trap_args[@]}")
}

function _jenkins_run_saved_trap_literal() {
   local signal="$1"
   shift || true
   local handler_literal="${1-}"
   shift || true

   local literal_var="_JENKINS_PREV_${signal}_TRAP_LITERAL"
   local handler_var="_JENKINS_PREV_${signal}_TRAP_HANDLER"
   if [[ -n "${!literal_var:-}" ]]; then
      handler_literal="${!literal_var}"
   elif [[ -n "${!handler_var:-}" ]]; then
      handler_literal="${!handler_var}"
   fi

   if [[ -z "$handler_literal" ]]; then
      return 0
   fi

   _jenkins_deduplicate_trap_tokens "$handler_var" "$@"
   local -a trap_args=("${_JENKINS_DEDUP_TRAP_ARGS[@]}")
   if (( ${#trap_args[@]} )); then
      set -- "${trap_args[@]}"
   else
      set --
   fi

   local -a handler_args=()
   eval "handler_args=( $handler_literal )"
   if (( ${#handler_args[@]} == 0 )); then
      return 0
   fi

   "${handler_args[@]}"
}

function _jenkins_register_rendered_manifest() {
   local manifest="$1"
   if [[ -n "$manifest" ]]; then
      _JENKINS_RENDERED_MANIFESTS+=("$manifest")
   fi
}

function _jenkins_cleanup_rendered_manifests() {
   local trap_source="${1:-EXIT}"

   if (( ${#_JENKINS_RENDERED_MANIFESTS[@]} )); then
      _cleanup_on_success "${_JENKINS_RENDERED_MANIFESTS[@]}"
      _JENKINS_RENDERED_MANIFESTS=()
   fi

   if [[ -n "$_JENKINS_PREV_EXIT_TRAP_CMD" ]]; then
      eval "$_JENKINS_PREV_EXIT_TRAP_CMD"
   else
      trap - EXIT
   fi

   if [[ -n "$_JENKINS_PREV_RETURN_TRAP_CMD" ]]; then
      eval "$_JENKINS_PREV_RETURN_TRAP_CMD"
   else
      trap - RETURN
   fi

   if [[ "$trap_source" != MANUAL ]]; then
      _JENKINS_PREV_EXIT_TRAP_CMD=""
      _JENKINS_PREV_EXIT_TRAP_HANDLER=""
      _JENKINS_PREV_RETURN_TRAP_CMD=""
      _JENKINS_PREV_RETURN_TRAP_HANDLER=""
   fi
}

function _jenkins_cleanup_and_return() {
   local rc="${1:-0}"
   _jenkins_cleanup_rendered_manifests MANUAL
   return "$rc"
}

function _create_jenkins_namespace() {
   jenkins_namespace="${1:-jenkins}"
   export namespace="${jenkins_namespace}"
   jenkins_namespace_template="$(dirname "$SOURCE")/etc/jenkins/jenkins-namespace.yaml.tmpl"
   if [[ ! -r "$jenkins_namespace_template" ]]; then
      echo "Jenkins namespace template file not found: $jenkins_namespace_template"
      exit 1
   fi
   yamlfile=$(mktemp -t jenkins-namespace.XXXXXX.yaml)
   trap '$(_cleanup_trap_command "$yamlfile")' EXIT
   # shellcheck disable=SC2086
   envsubst < "$jenkins_namespace_template" > "$yamlfile"

   if _kubectl --no-exit get namespace "$jenkins_namespace" >/dev/null 2>&1; then
      echo "Namespace $jenkins_namespace already exists, skip"
   else
      _kubectl apply -f "$yamlfile" >/dev/null 2>&1
      echo "Namespace $jenkins_namespace created"
   fi

   trap '$(_cleanup_trap_command "$yamlfile")' RETURN
}

function _create_jenkins_pv_pvc() {
   local jenkins_namespace=$1
   local cluster_name="${CLUSTER_NAME:-}"

   if [[ -z "$cluster_name" ]]; then
      cluster_name=$(_jenkins_resolve_cluster_name 2>/dev/null || true)
   fi

   if ! _jenkins_require_hostpath_mounts "$cluster_name"; then
      local host_dir
      host_dir=$(_jenkins_hostpath_dir)
      local missing="${JENKINS_MISSING_HOSTPATH_NODES:-unknown}"
      printf 'ERROR: hostPath mount %s missing on nodes: %s\n' "$host_dir" "$missing" >&2
      printf 'ERROR: Update your cluster configuration via create_cluster and retry.\n' >&2
      return 1
   fi

   jenkins_pv_template="$(dirname "$SOURCE")/etc/jenkins/jenkins-home-pv.yaml.tmpl"
   if [[ ! -r "$jenkins_pv_template" ]]; then
      _err "Jenkins PV template file not found: $jenkins_pv_template"
   fi

   jenkinsyamfile=$(mktemp -t jenkins-home-pv.XXXXXX.yaml)
   trap '$(_cleanup_trap_command "$jenkinsyamfile")' EXIT
   export JENKINS_NAMESPACE="$jenkins_namespace"
   envsubst < "$jenkins_pv_template" > "$jenkinsyamfile"
   _kubectl apply -f "$jenkinsyamfile" -n "$jenkins_namespace"

   trap '$(_cleanup_trap_command "$jenkinsyamfile")' RETURN
}

function _ensure_jenkins_cert() {
   local vault_namespace="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local vault_release="${2:-$VAULT_RELEASE_DEFAULT}"
   local k8s_namespace="${VAULT_PKI_SECRET_NS:-istio-system}"
   local secret_name="${VAULT_PKI_SECRET_NAME:-jenkins-tls}"
   local common_name="${VAULT_PKI_LEAF_HOST:-jenkins.dev.local.me}"

   if _kubectl --no-exit -n "$k8s_namespace" \
      get secret "$secret_name" >/dev/null 2>&1; then
      echo "TLS secret $secret_name already exists, skip"
      return 0
   fi

   # Check if PKI secrets engine is enabled using authenticated vault_exec
   if ! _vault_exec --no-exit "$vault_namespace" "vault secrets list" "$vault_release" 2>/dev/null | grep -q "^pki/"; then
      _vault_exec "$vault_namespace" "vault secrets enable pki" "$vault_release"
      _vault_exec "$vault_namespace" "vault secrets tune -max-lease-ttl=87600h pki" "$vault_release"
      _vault_exec "$vault_namespace" "vault write pki/root/generate/internal common_name=dev.local.me ttl=87600h" "$vault_release"
   fi

   local allowed_domains_input="${VAULT_PKI_ALLOWED:-}"
   allowed_domains_input="${allowed_domains_input//[[:space:]]/}"
   local allowed_domains="" allow_subdomains_opt=""
   if [[ -n "$allowed_domains_input" ]]; then
      allowed_domains="$allowed_domains_input"
      if [[ "$allowed_domains" != *","* && "$allowed_domains" != *"*"* ]]; then
         allow_subdomains_opt="allow_subdomains=true"
      fi
   else
      local host_no_wildcard="$common_name"
      if [[ "$host_no_wildcard" == \*.* ]]; then
         host_no_wildcard="${host_no_wildcard#*.}"
      fi
      if [[ "$host_no_wildcard" =~ \.(nip\.io|sslip\.io)$ ]]; then
         allowed_domains="${BASH_REMATCH[1]}"
         allow_subdomains_opt="allow_subdomains=true"
      elif [[ "$host_no_wildcard" == *.*.* ]]; then
         allowed_domains="${host_no_wildcard#*.}"
         allow_subdomains_opt="allow_subdomains=true"
      else
         allowed_domains="$host_no_wildcard"
      fi
   fi

   local -a _jenkins_role_args=("allowed_domains=${allowed_domains}")
   if [[ -n "$allow_subdomains_opt" ]]; then
      _jenkins_role_args+=("$allow_subdomains_opt")
   fi
   _jenkins_role_args+=("max_ttl=72h")

   # Build vault write command with all arguments
   local role_cmd="vault write pki/roles/jenkins"
   for arg in "${_jenkins_role_args[@]}"; do
      role_cmd+=" $arg"
   done
   _vault_exec "$vault_namespace" "$role_cmd" "$vault_release"

   local json cert_file key_file
   json=$(_vault_exec "$vault_namespace" "vault write -format=json pki/issue/jenkins common_name=$common_name ttl=72h" "$vault_release")

   cert_file=$(mktemp -t jenkins-cert.XXXXXX.pem)
   key_file=$(mktemp -t jenkins-key.XXXXXX.pem)

   trap '$(_cleanup_trap_command "$cert_file" "$key_file")' RETURN
   trap '$(_cleanup_trap_command "$cert_file" "$key_file")' EXIT

   echo "$json" | jq -r '.data.certificate' > "$cert_file"
   echo "$json" | jq -r '.data.ca_chain[]?' >> "$cert_file"
   echo "$json" | jq -r '.data.private_key' > "$key_file"

   _kubectl -n "$k8s_namespace" create secret tls "$secret_name" \
      --cert="$cert_file" --key="$key_file"

}

function _deploy_jenkins_image() {
   local ns="${1:-jenkins}"

   # shellcheck disable=SC2155
   local jenkins_admin_sha="$(_bw_lookup_secret "jenkins-admin" "jenkins" | _sha256_12 )"
   local jenkins_admin_passwd_sha="$(_bw_lookup_secret "jenkins-admin-password" "jenkins" \
      | _sha256_12 )"
   # shellcheck disable=SC2155
   local k3d_jenkins_admin_sha=$(_kubectl -n "$ns" get secret jenkins-admin -o jsonpath='{.data.username}' | base64 --decode | _sha256_12)

   if ! _is_same_token "$jenkins_admin_sha" "$k3d_jenkins_admin_sha"; then
      _err "Jenkins admin user in k3d does NOT match Bitwarden!" >&2
   else
      _info "Jenkins admin user in k3d matches Bitwarden."
   fi
}

function _jenkins_format_pull_failure_details() {
   local failure_fields="$1"
   local failure_reason="" failure_message="" details=""
   local IFS=$'\t'
   read -r failure_reason failure_message <<< "$failure_fields"
   if [[ -n "$failure_reason" && -n "$failure_message" ]]; then
      details="${failure_reason}; ${failure_message}"
   elif [[ -n "$failure_reason" ]]; then
      details="$failure_reason"
   elif [[ -n "$failure_message" ]]; then
      details="$failure_message"
   else
      details="image pull failure"
   fi
   printf '%s' "$details"
}

function _jenkins_warn_on_cert_rotator_pull_failure() {
   local ns="$1"

   if [[ -z "${ns:-}" ]]; then
      return 0
   fi

   if ! command -v jq >/dev/null 2>&1; then
      return 0
   fi

   local pods_json=""
   if ! pods_json=$(_kubectl --no-exit --quiet -n "$ns" get pods -l job-name -o json 2>/dev/null); then
      return 0
   fi

   if [[ -z "$pods_json" ]]; then
      return 0
   fi

   local job_prefix="${JENKINS_CERT_ROTATOR_NAME:-jenkins-cert-rotator}"
   local failure_fields
   failure_fields=$(printf '%s\n' "$pods_json" | jq -r --arg prefix "$job_prefix" '
      [ .items[]
        | select(.metadata.labels["job-name"]? | startswith($prefix))
        | ( .status.containerStatuses[]?, .status.initContainerStatuses[]? )
        | select(.state.waiting.reason? | ( . == "ErrImagePull" or . == "ImagePullBackOff"))
        | {reason: (.state.waiting.reason // ""), message: (.state.waiting.message // "")}
      ] | if length > 0 then (.[0].reason + "\t" + .[0].message) else "" end
   ')

   if [[ -n "$failure_fields" ]]; then
      local failure_details
      failure_details=$(_jenkins_format_pull_failure_details "$failure_fields")
      _warn "Jenkins cert rotator pods are failing to pull their image (${failure_details}). Set JENKINS_CERT_ROTATOR_IMAGE or edit scripts/etc/jenkins/jenkins-vars.sh to point at an accessible registry."
   fi
}

function _jenkins_adopt_admin_secret() {
   local ns="${1:-jenkins}"
   local secret="${2:-jenkins}"
   local release="${3:-jenkins}"
   local managed_by=""
   local rel_name=""
   local rel_ns=""

   if ! _kubectl --no-exit -n "$ns" get secret "$secret" >/dev/null 2>&1; then
      return 1
   fi

   managed_by=$(_kubectl --no-exit -n "$ns" get secret "$secret" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null || true)
   rel_name=$(_kubectl --no-exit -n "$ns" get secret "$secret" -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}' 2>/dev/null || true)
   rel_ns=$(_kubectl --no-exit -n "$ns" get secret "$secret" -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-namespace}' 2>/dev/null || true)

   if [[ "$managed_by" == "Helm" && "$rel_name" == "$release" && "$rel_ns" == "$ns" ]]; then
      return 0
   fi

   if ! _kubectl -n "$ns" label secret "$secret" app.kubernetes.io/managed-by=Helm --overwrite; then
      return 1
   fi
   if ! _kubectl -n "$ns" annotate secret "$secret" meta.helm.sh/release-name="$release" --overwrite; then
      return 1
   fi
   if ! _kubectl -n "$ns" annotate secret "$secret" meta.helm.sh/release-namespace="$ns" --overwrite; then
      return 1
   fi

   return 0
}

function _jenkins_running_on_wsl() {
   if declare -f _is_wsl >/dev/null 2>&1; then
      _is_wsl
      return $?
   fi

   return 1
}

function _jenkins_provider_is_k3s() {
   if declare -f _cluster_provider_is >/dev/null 2>&1; then
      if _cluster_provider_is k3s; then
         return 0
      fi
      return 1
   fi

   local provider="${CLUSTER_PROVIDER:-${K3D_MANAGER_PROVIDER:-${K3DMGR_PROVIDER:-${K3D_MANAGER_CLUSTER_PROVIDER:-}}}}"
   provider="$(printf '%s' "$provider" | tr '[:upper:]' '[:lower:]')"
   [[ "$provider" == "k3s" ]]
}

function _jenkins_detect_node_ip() {
   if ! declare -f _kubectl >/dev/null 2>&1; then
      return 1
   fi

   local override="${JENKINS_WSL_NODE_IP:-}"
   override="${override//$'\r'/}"
   override="${override//$'\n'/}"
   override="${override## }"
   override="${override%% }"
   if [[ "$override" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      printf '%s\n' "$override"
      return 0
   fi

   local node_ip=""
   node_ip=$(_kubectl --no-exit --quiet get nodes -o \
      jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
   node_ip="${node_ip//$'\r'/}"
   node_ip="${node_ip//$'\n'/}"
   node_ip="${node_ip## }"
   node_ip="${node_ip%% }"

   if [[ "$node_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      printf '%s\n' "$node_ip"
      return 0
   fi

   return 1
}

function _jenkins_configure_leaf_host_defaults() {
   if [[ -n "${VAULT_PKI_LEAF_HOST:-}" ]]; then
      return 0
   fi

   if _jenkins_provider_is_k3s && _jenkins_running_on_wsl; then
      local node_ip=""
      if node_ip=$(_jenkins_detect_node_ip); then
         export VAULT_PKI_LEAF_HOST="jenkins.${node_ip}.sslip.io"
         return 0
      fi
   fi

   return 0
}

function _deploy_jenkins_ldap() {
   local vault_ns="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local vault_release="${2:-${VAULT_RELEASE:-$VAULT_RELEASE_DEFAULT}}"
   local ldap_ns="${LDAP_NAMESPACE:-directory}"
   local ldap_release="${LDAP_RELEASE:-openldap}"

   _info "[jenkins] deploying LDAP integration to ${ldap_ns}/${ldap_release}"

   # Use directory service interface if available, otherwise fallback to direct LDAP calls
   if declare -f dirservice_init >/dev/null 2>&1; then
      # New directory service interface
      _info "[jenkins] using directory service abstraction"
      export DIRECTORY_SERVICE_PROVIDER="${DIRECTORY_SERVICE_PROVIDER:-openldap}"

      if ! dirservice_init "$ldap_ns" "$ldap_release" "$vault_ns" "$vault_release"; then
         _err "[jenkins] directory service initialization failed"
      fi
   else
      # Fallback to direct LDAP plugin (backward compatibility)
      _info "[jenkins] using legacy LDAP plugin"

      # Source LDAP plugin if not already loaded
      if ! declare -f deploy_ldap >/dev/null 2>&1; then
         local ldap_plugin="$PLUGINS_DIR/ldap.sh"
         if [[ ! -r "$ldap_plugin" ]]; then
            _err "[jenkins] LDAP plugin not found at ${ldap_plugin}"
         fi
         # shellcheck disable=SC1090
         source "$ldap_plugin"
      fi

      # Deploy LDAP directory
      if [[ "$enable_vault" == "1" ]]; then
         if ! deploy_ldap --namespace "$ldap_ns" --release "$ldap_release" --enable-vault; then
            _err "[jenkins] LDAP deployment failed"
         fi
      else
         if ! deploy_ldap --namespace "$ldap_ns" --release "$ldap_release"; then
            _err "[jenkins] LDAP deployment failed"
         fi
      fi

      # Seed Jenkins service account in Vault LDAP
      if declare -f _vault_seed_ldap_service_accounts >/dev/null 2>&1; then
         _info "[jenkins] seeding Jenkins LDAP service account in Vault"
         _vault_seed_ldap_service_accounts "$vault_ns" "$vault_release"
      else
         _warn "[jenkins] _vault_seed_ldap_service_accounts not available; skipping service account seed"
      fi
   fi
}

function _deploy_jenkins_ad() {
   local vault_ns="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local vault_release="${2:-${VAULT_RELEASE:-$VAULT_RELEASE_DEFAULT}}"
   local ad_ns="${LDAP_NAMESPACE:-directory}"
   local ad_release="${LDAP_RELEASE:-openldap}"

   _info "[jenkins] deploying AD schema testing (OpenLDAP with AD schema) to ${ad_ns}/${ad_release}"

   # Source LDAP plugin if not already loaded
   if ! declare -f deploy_ad >/dev/null 2>&1; then
      local ldap_plugin="$PLUGINS_DIR/ldap.sh"
      if [[ ! -r "$ldap_plugin" ]]; then
         _err "[jenkins] LDAP plugin not found at ${ldap_plugin}"
      fi
      # shellcheck disable=SC1090
      source "$ldap_plugin"
   fi

   # Deploy OpenLDAP with AD schema
   if [[ "$enable_vault" == "1" ]]; then
      if ! deploy_ad --namespace "$ad_ns" --release "$ad_release" --enable-vault; then
         _err "[jenkins] AD schema deployment failed"
      fi
   else
      if ! deploy_ad --namespace "$ad_ns" --release "$ad_release"; then
         _err "[jenkins] AD schema deployment failed"
      fi
   fi

   # Seed Jenkins service account in Vault LDAP
   if declare -f _vault_seed_ldap_service_accounts >/dev/null 2>&1; then
      _info "[jenkins] seeding Jenkins AD service account in Vault"
      _vault_seed_ldap_service_accounts "$vault_ns" "$vault_release"
   else
      _warn "[jenkins] _vault_seed_ldap_service_accounts not available; skipping service account seed"
   fi
}

function _validate_ad_connectivity() {
   local ad_domain="${1:?AD domain required}"
   local ad_server="${2:-}"
   local require_tls="${3:-true}"

   _info "[jenkins] validating Active Directory connectivity..."

   # Determine which host to test
   local test_host="$ad_domain"
   if [[ -n "$ad_server" ]]; then
      # If AD_SERVER is set, use the first one (comma-separated list)
      test_host="${ad_server%%,*}"
      test_host="${test_host// /}"  # trim whitespace
   fi

   # Test DNS resolution
   _info "[jenkins] checking DNS resolution for: $test_host"
   if ! host "$test_host" >/dev/null 2>&1 && ! nslookup "$test_host" >/dev/null 2>&1 && ! getent hosts "$test_host" >/dev/null 2>&1; then
      _err "[jenkins] AD server '$test_host' cannot be resolved via DNS. Please check AD_DOMAIN or AD_SERVER configuration."
   fi
   _info "[jenkins] DNS resolution successful for $test_host"

   # Determine LDAP port based on TLS requirement
   local ldap_port
   if [[ "$require_tls" == "true" ]]; then
      ldap_port=636  # LDAPS
      _info "[jenkins] testing LDAPS connectivity on port 636..."
   else
      ldap_port=389  # LDAP
      _info "[jenkins] testing LDAP connectivity on port 389..."
   fi

   # Test port connectivity using timeout and nc/telnet/bash
   local connection_test_result=1
   if command -v nc >/dev/null 2>&1; then
      # Use netcat if available
      if timeout 5 nc -z "$test_host" "$ldap_port" 2>/dev/null; then
         connection_test_result=0
      fi
   elif command -v timeout >/dev/null 2>&1 && [[ -e /dev/tcp ]]; then
      # Use bash TCP redirection with timeout
      if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$test_host/$ldap_port" 2>/dev/null; then
         connection_test_result=0
      fi
   else
      # Fallback: just warn that we can't test connectivity
      _warn "[jenkins] cannot test port connectivity (nc or timeout not available), skipping port check"
      return 0
   fi

   if (( connection_test_result != 0 )); then
      printf '\n' >&2
      printf 'ERROR: [jenkins] Cannot connect to AD server '\''%s'\'' on port %s\n' "$test_host" "$ldap_port" >&2
      printf 'ERROR: \n' >&2
      printf 'ERROR: Please verify:\n' >&2
      printf 'ERROR:   1. AD server is running and accessible from this host\n' >&2
      printf 'ERROR:   2. Firewall allows connections to port %s\n' "$ldap_port" >&2
      printf 'ERROR:   3. AD_DOMAIN='\''%s'\'' or AD_SERVER='\''%s'\'' is correct\n' "$ad_domain" "${ad_server:-<not set>}" >&2
      printf 'ERROR: \n' >&2
      printf 'ERROR: To skip this validation for testing, use: --skip-ad-validation\n' >&2
      printf '\n' >&2
      _err "[jenkins] AD connectivity validation failed. Deployment aborted."
   fi

   _info "[jenkins] Active Directory connectivity validated successfully"
   return 0
}

function _jenkins_ip_is_private() {
   local candidate="${1:-}"
   [[ "$candidate" =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]]
}

function _jenkins_ip_is_loopback() {
   local candidate="${1:-}"
   [[ "$candidate" =~ ^127\. ]]
}

function _jenkins_resolve_smoke_target() {
   local namespace="$1" smoke_url_override="$2" user_ip_override="$3"

   local jenkins_host=""
   jenkins_host=$(_kubectl --no-exit -n "$namespace" get vs jenkins -o jsonpath='{.spec.hosts[0]}' 2>/dev/null || echo "")
   if [[ -z "$jenkins_host" ]]; then
      jenkins_host="${VAULT_PKI_LEAF_HOST:-jenkins.dev.local.me}"
      _warn "[jenkins] could not detect Jenkins hostname from VirtualService, using default: ${jenkins_host}"
   fi

   local ingress_ip=""
   if [[ -z "$smoke_url_override" && -z "$user_ip_override" ]]; then
      ingress_ip=$(_kubectl --no-exit -n istio-system get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
      if [[ -z "$ingress_ip" ]]; then
         _warn "[jenkins] could not detect ingress IP; relying on smoke script lookup"
      fi
   fi

   local use_port_forward=0
   if [[ -z "$smoke_url_override" && -z "$user_ip_override" && -n "$ingress_ip" ]]; then
      if _is_mac && _jenkins_ip_is_private "$ingress_ip" && ! _jenkins_ip_is_loopback "$ingress_ip"; then
         use_port_forward=1
      fi
   fi

   _JENKINS_SMOKE_HOST="$jenkins_host"
   _JENKINS_SMOKE_INGRESS_IP="$ingress_ip"
   _JENKINS_SMOKE_USE_PORT_FORWARD="$use_port_forward"
}

function _jenkins_run_smoke_via_port_forward() {
   local pf_namespace="$1" pf_service="$2" pf_port="$3"
   _JENKINS_SMOKE_PF_RC=0
   (
      local pf_pid="" port_forward_log="" preserve_log=0
      port_forward_log=$(mktemp -t jenkins-port-forward.XXXXXX.log 2>/dev/null || printf '')
      cleanup_pf() {
         if [[ -n "$pf_pid" ]]; then
            kill "$pf_pid" 2>/dev/null || true
            wait "$pf_pid" 2>/dev/null || true
         fi
         if (( ! preserve_log )) && [[ -n "$port_forward_log" ]]; then
            rm -f "$port_forward_log"
         fi
      }
      trap cleanup_pf EXIT INT TERM
      local log_target="${port_forward_log:-/dev/null}"
      kubectl -n "$pf_namespace" port-forward "svc/${pf_service}" "${pf_port}:443" >"$log_target" 2>&1 &
      pf_pid=$!
      local ready=0
      if command -v nc >/dev/null 2>&1; then
         local attempt
         for (( attempt=0; attempt<10; attempt++ )); do
            kill -0 "$pf_pid" 2>/dev/null || break
            if nc -z 127.0.0.1 "$pf_port" >/dev/null 2>&1; then
               ready=1
               break
            fi
            sleep 0.5
         done
      else
         _warn "[jenkins] nc not found; waiting 5 seconds for port-forward readiness"
         sleep 5
         kill -0 "$pf_pid" 2>/dev/null && ready=1
      fi
      if (( ! ready )); then
         preserve_log=1
         if [[ -n "$port_forward_log" ]]; then
            echo "ERROR: [jenkins] kubectl port-forward failed to become ready (see $port_forward_log)" >&2
            cat "$port_forward_log" >&2 || true
         else
            echo "ERROR: [jenkins] kubectl port-forward failed to become ready" >&2
         fi
         exit 1
      fi
      if (( ${#_JENKINS_SMOKE_ENV[@]} )); then
         _run_command -- env "${_JENKINS_SMOKE_ENV[@]}" "${_JENKINS_SMOKE_CMD[@]}"
      else
         _run_command -- "${_JENKINS_SMOKE_CMD[@]}"
      fi
   )
   _JENKINS_SMOKE_PF_RC=$?
}

function _jenkins_exec_smoke_cmd() {
   if (( ${#_JENKINS_SMOKE_ENV[@]} )); then
     _run_command -- env "${_JENKINS_SMOKE_ENV[@]}" "${_JENKINS_SMOKE_CMD[@]}"
   else
     _run_command -- "${_JENKINS_SMOKE_CMD[@]}"
   fi
}

function _jenkins_run_smoke_test() {
   local namespace="${1:-jenkins}"
   local enable_ldap="${2:-0}"
   local enable_ad="${3:-0}"
   local enable_ad_prod="${4:-0}"
   local smoke_url_override="${JENKINS_SMOKE_URL:-}"
   local user_ip_override="${JENKINS_SMOKE_IP_OVERRIDE:-}"

   if [[ -n "${BATS_TEST_DIRNAME:-}" ]] || [[ -n "${BATS_TEST_TMPDIR:-}" ]]; then
      return 0
   fi

   local smoke_script="${SCRIPT_DIR}/../bin/smoke-test-jenkins.sh"
   if [[ ! -x "$smoke_script" ]]; then
      if [[ -r "$smoke_script" ]]; then
         _warn "[jenkins] smoke test script not executable: ${smoke_script}"
      else
         _warn "[jenkins] smoke test script missing: ${smoke_script}"
      fi
      return 0
   fi

   local auth_mode="default"
   if (( enable_ad_prod )); then
      auth_mode="ad"
   elif (( enable_ad )); then
      auth_mode="ad"
   elif (( enable_ldap )); then
      auth_mode="ldap"
   fi

   _jenkins_resolve_smoke_target "$namespace" "$smoke_url_override" "$user_ip_override"
   local jenkins_host="$_JENKINS_SMOKE_HOST"
   local ingress_ip="$_JENKINS_SMOKE_INGRESS_IP"
   local use_port_forward="${_JENKINS_SMOKE_USE_PORT_FORWARD:-0}"

   _JENKINS_SMOKE_ENV=()
   if [[ -z "$user_ip_override" ]]; then
      if (( use_port_forward )); then
         _JENKINS_SMOKE_ENV=("JENKINS_SMOKE_IP_OVERRIDE=127.0.0.1")
      elif [[ -n "$ingress_ip" ]]; then
         _JENKINS_SMOKE_ENV=("JENKINS_SMOKE_IP_OVERRIDE=$ingress_ip")
      fi
   fi

   local smoke_port=443
   local pf_port=8443
   local pf_namespace="istio-system"
   local pf_service="istio-ingressgateway"
   (( use_port_forward )) && smoke_port=$pf_port

   _JENKINS_SMOKE_CMD=("$smoke_script" "$namespace" "$jenkins_host" "$smoke_port" "$auth_mode")
   _info "[jenkins] running smoke test (namespace=${namespace}, host=${jenkins_host}, auth_mode=${auth_mode})"

   local smoke_rc=0
   if (( use_port_forward )); then
      case "${K3DM_DEPLOY_DRY_RUN:-0}" in
         1)
            _run_command -- kubectl -n "$pf_namespace" port-forward "svc/${pf_service}" "${pf_port}:443"
            _jenkins_exec_smoke_cmd
            smoke_rc=$?
            ;;
         *)
            _info "[jenkins] ingress IP ${ingress_ip} is private; using kubectl port-forward to ${pf_namespace}/${pf_service} -> 127.0.0.1:${pf_port}"
            _jenkins_run_smoke_via_port_forward "$pf_namespace" "$pf_service" "$pf_port"
            smoke_rc="$_JENKINS_SMOKE_PF_RC"
            ;;
      esac
   else
      _jenkins_exec_smoke_cmd
      smoke_rc=$?
   fi

   if (( smoke_rc == 0 )); then
      _info "[jenkins] smoke test passed"
      return 0
   fi
   return 1
}

function _jenkins_deploy_infra_prereqs() {
   local enable_vault="$1"
   local enable_ad="$2"
   local enable_ldap="$3"
   local vault_namespace="$4"
   local vault_release="$5"
   local enable_ad_prod="${JENKINS_AD_PROD_ENABLED:-0}"

   if (( enable_vault )); then
      deploy_eso
      _info "[jenkins] deploying Vault to ${vault_namespace}/${vault_release}"
      deploy_vault "$vault_namespace" "$vault_release"
   else
      _info "[jenkins] skipping Vault deployment (using existing instance)"
   fi

   if (( enable_ad_prod )); then
      _info "[jenkins] production Active Directory enabled; skipping local directory service deployment"
   elif (( enable_ad )); then
      _deploy_jenkins_ad "$vault_namespace" "$vault_release"
   elif (( enable_ldap )); then
      _deploy_jenkins_ldap "$vault_namespace" "$vault_release"
   else
      _info "[jenkins] skipping directory service deployment"
   fi
}

function _jenkins_collect_vault_prefix_arg() {
   local -a secret_prefixes=()
   if [[ -n "${JENKINS_VAULT_POLICY_PREFIX:-}" ]]; then
      local -a configured_array=()
      read -r -a configured_array <<< "${JENKINS_VAULT_POLICY_PREFIX//,/ }"
      secret_prefixes+=("${configured_array[@]}")
   fi

   local -a secret_paths=("${JENKINS_ADMIN_VAULT_PATH:-}" "${JENKINS_LDAP_VAULT_PATH:-}")
   local path
   for path in "${secret_paths[@]}"; do
      [[ -z "$path" ]] && continue
      secret_prefixes+=("$path")
   done

   local -a unique_prefixes=()
   for path in "${secret_prefixes[@]}"; do
      [[ -z "$path" ]] && continue
      local trimmed="${path#/}"
      trimmed="${trimmed%/}"
      [[ -z "$trimmed" ]] && continue
      local seen=0 existing
      for existing in "${unique_prefixes[@]}"; do
         if [[ "$existing" == "$trimmed" ]]; then
            seen=1
            break
         fi
      done
      (( seen )) && continue
      unique_prefixes+=("$trimmed")
   done

   local result=""
   for path in "${unique_prefixes[@]}"; do
      [[ -n "$result" ]] && result+=","
      result+="$path"
   done
   _JENKINS_VAULT_PREFIX_ARG="$result"
}

function _jenkins_ensure_secrets_ready() {
   local vault_namespace="$1"
   local vault_release="$2"
   local jenkins_namespace="$3"

   _jenkins_collect_vault_prefix_arg

   if ! _vault_configure_secret_reader_role \
         "$vault_namespace" "$vault_release" \
         "$JENKINS_ESO_SERVICE_ACCOUNT" "$jenkins_namespace" \
         "$JENKINS_VAULT_KV_MOUNT" "$_JENKINS_VAULT_PREFIX_ARG" \
         "$JENKINS_ESO_ROLE"; then
      _err "[jenkins] failed to configure Vault role ${JENKINS_ESO_ROLE} for namespace ${jenkins_namespace}"
      return 1
   fi

   if ! _jenkins_apply_eso_resources "$jenkins_namespace"; then
      _err "[jenkins] failed to apply ESO manifests for namespace ${jenkins_namespace}"
      return 1
   fi

   if ! _jenkins_wait_for_secret "$jenkins_namespace" "$JENKINS_ADMIN_SECRET_NAME"; then
      _err "[jenkins] Vault-sourced secret ${JENKINS_ADMIN_SECRET_NAME} not available"
      return 1
   fi

   if (( JENKINS_LDAP_ENABLED )); then
      if ! _jenkins_wait_for_secret "$jenkins_namespace" "$JENKINS_LDAP_SECRET_NAME"; then
         _err "[jenkins] Vault-sourced secret ${JENKINS_LDAP_SECRET_NAME} not available"
         return 1
      fi
   fi
}

function _jenkins_deploy_with_retry() {
   local jenkins_namespace="$1"
   local vault_namespace="$2"
   local vault_release="$3"
   local enable_ldap="$4"
   local enable_ad="$5"
   local enable_ad_prod="$6"

   local max_attempts="${JENKINS_DEPLOY_RETRIES:-3}"
   if ! [[ "$max_attempts" =~ ^[0-9]+$ ]] || (( max_attempts < 1 )); then
      max_attempts=3
   fi

   local attempt deploy_rc wait_rc selector
   selector='app.kubernetes.io/component=jenkins-controller'

   for (( attempt=1; attempt<=max_attempts; attempt++ )); do
      _deploy_jenkins "$jenkins_namespace" "$vault_namespace" "$vault_release"
      deploy_rc=$?
      wait_rc=0

      if (( deploy_rc == 0 )); then
         if _wait_for_jenkins_ready "$jenkins_namespace"; then
            _jenkins_run_smoke_test "$jenkins_namespace" "$enable_ldap" "$enable_ad" "$enable_ad_prod" || \
               _warn "[jenkins] smoke test failed; inspect output above"
            return 0
         fi
         wait_rc=$?
      else
         wait_rc=$deploy_rc
      fi

      if (( attempt >= max_attempts )); then
         printf 'ERROR: Jenkins deployment failed after %d attempt(s).\n' "$attempt" >&2
         return "$wait_rc"
      fi

      _warn "Jenkins deployment attempt ${attempt} failed (rc=${wait_rc}); retrying..."
      _kubectl --no-exit --quiet -n "$jenkins_namespace" delete pod -l "$selector" --ignore-not-found >/dev/null 2>&1 || true
      sleep 10
   done
}

function _jenkins_restore_trace() {
   local should_restore="${1:-0}"
   if (( should_restore )); then
      set -x
   fi
}

function deploy_jenkins() {
   if [[ "${ENABLE_JENKINS:-0}" != "1" ]]; then
      _info "[jenkins] skipped — set ENABLE_JENKINS=1 to deploy"
      return 0
   fi
   local jenkins_namespace=""
   local vault_namespace=""
   local vault_release=""
   local enable_ldap="${JENKINS_LDAP_ENABLED:-0}"
   local enable_ad="${JENKINS_AD_ENABLED:-0}"
   local enable_ad_prod="${JENKINS_AD_PROD_ENABLED:-0}"
   local enable_vault="${JENKINS_VAULT_ENABLED:-1}"
   local enable_mfa="${JENKINS_MFA_ENABLED:-1}"
   local skip_ad_validation="${JENKINS_SKIP_AD_VALIDATION:-0}"
   local restore_trace=0
   local arg_count=$#

   case $- in
      *x*) restore_trace=1 ;;
   esac

   # Show help if no arguments provided
   if [[ $arg_count -eq 0 ]]; then
      cat <<EOF
Usage: deploy_jenkins [options] [namespace] [vault-namespace] [vault-release]

Options:
  --namespace <ns>           Jenkins namespace (default: jenkins)
  --vault-namespace <ns>     Vault namespace (default: ${VAULT_NS_DEFAULT:-vault})
  --vault-release <name>     Vault release name (default: ${VAULT_RELEASE_DEFAULT:-vault})
  --enable-ldap              Deploy standard LDAP integration (default: disabled)
  --enable-ad                Deploy AD schema testing (OpenLDAP with AD schema) (default: disabled)
  --enable-ad-prod           Deploy production Active Directory integration (default: disabled)
  --skip-ad-validation       Skip Active Directory connectivity validation (for testing)
  --disable-ldap             Skip directory service deployment
  --enable-vault             Deploy Vault (default: disabled)
  --disable-vault            Skip Vault deployment (use existing)
  --disable-mfa              Disable TOTP/MFA plugin (enabled by default)
  -h, --help                 Show this help message

Feature Flags (environment variables):
  JENKINS_LDAP_ENABLED=0|1       Enable LDAP auto-deployment (default: 0)
  JENKINS_AD_ENABLED=0|1         Enable AD testing auto-deployment (default: 0)
  JENKINS_AD_PROD_ENABLED=0|1    Enable production AD auto-deployment (default: 0)
  JENKINS_VAULT_ENABLED=0|1      Enable Vault auto-deployment (default: 0)

Active Directory Production Setup:
  When using --enable-ad-prod, configure these environment variables:
    AD_DOMAIN       Domain name (e.g., corp.example.com)
    AD_SERVER       DC servers (optional, comma-separated)
    AD_VAULT_PATH   Vault path for AD credentials (default: secret/data/jenkins/ad-credentials)

  Store credentials in Vault before deployment:
    vault kv put secret/jenkins/ad-credentials \\
      username="svc-jenkins@corp.example.com" \\
      password="..."

Examples:
  # Show this help message
  deploy_jenkins

  # Minimal deployment (Jenkins only, no directory service, no Vault)
  deploy_jenkins --disable-ldap --disable-vault

  # Standard LDAP integration
  deploy_jenkins --enable-ldap --enable-vault

  # AD schema testing (local OpenLDAP with AD schema)
  deploy_jenkins --enable-ad --enable-vault

  # Production Active Directory integration
  export AD_DOMAIN="corp.example.com"
  deploy_jenkins --enable-ad-prod --enable-vault

  # Deploy with Vault integration only
  deploy_jenkins --enable-vault

  # Deploy to custom namespace with AD testing
  deploy_jenkins --namespace jenkins-prod --enable-ad --enable-vault

Positional arguments (backwards compatible):
  deploy_jenkins [namespace] [vault-namespace] [vault-release]
EOF
      _jenkins_restore_trace "$restore_trace"
      return 0
   fi

   if [[ "${CLUSTER_ROLE:-infra}" == "app" ]]; then
      _info "[jenkins] CLUSTER_ROLE=app — skipping deploy_jenkins"
      _jenkins_restore_trace "$restore_trace"
      return 0
   fi

   # Parse arguments
   while [[ $# -gt 0 ]]; do
      case "$1" in
         -h|--help)
            cat <<EOF
Usage: deploy_jenkins [options] [namespace] [vault-namespace] [vault-release]

Options:
  --namespace <ns>           Jenkins namespace (default: jenkins)
  --vault-namespace <ns>     Vault namespace (default: ${VAULT_NS_DEFAULT:-vault})
  --vault-release <name>     Vault release name (default: ${VAULT_RELEASE_DEFAULT:-vault})
  --enable-ldap              Deploy standard LDAP integration (default: disabled)
  --enable-ad                Deploy AD schema testing (OpenLDAP with AD schema) (default: disabled)
  --enable-ad-prod           Deploy production Active Directory integration (default: disabled)
  --skip-ad-validation       Skip Active Directory connectivity validation (for testing)
  --disable-ldap             Skip directory service deployment
  --enable-vault             Deploy Vault (default: disabled)
  --disable-vault            Skip Vault deployment (use existing)
  --disable-mfa              Disable TOTP/MFA plugin (enabled by default)
  -h, --help                 Show this help message

Feature Flags (environment variables):
  JENKINS_LDAP_ENABLED=0|1       Enable LDAP auto-deployment (default: 0)
  JENKINS_AD_ENABLED=0|1         Enable AD testing auto-deployment (default: 0)
  JENKINS_AD_PROD_ENABLED=0|1    Enable production AD auto-deployment (default: 0)
  JENKINS_VAULT_ENABLED=0|1      Enable Vault auto-deployment (default: 0)

Active Directory Production Setup:
  When using --enable-ad-prod, configure these environment variables:
    AD_DOMAIN       Domain name (e.g., corp.example.com)
    AD_SERVER       DC servers (optional, comma-separated)
    AD_VAULT_PATH   Vault path for AD credentials (default: secret/data/jenkins/ad-credentials)

  Store credentials in Vault before deployment:
    vault kv put secret/jenkins/ad-credentials \\
      username="svc-jenkins@corp.example.com" \\
      password="..."

Examples:
  # Minimal deployment (Jenkins only, no directory service, no Vault)
  deploy_jenkins

  # Standard LDAP integration
  deploy_jenkins --enable-ldap --enable-vault

  # AD schema testing (local OpenLDAP with AD schema)
  deploy_jenkins --enable-ad --enable-vault

  # Production Active Directory integration
  export AD_DOMAIN="corp.example.com"
  deploy_jenkins --enable-ad-prod --enable-vault

  # Deploy with Vault integration only
  deploy_jenkins --enable-vault

  # Deploy to custom namespace with AD testing
  deploy_jenkins --namespace jenkins-prod --enable-ad --enable-vault

Positional arguments (backwards compatible):
  deploy_jenkins [namespace] [vault-namespace] [vault-release]
EOF
            _jenkins_restore_trace "$restore_trace"
            return 0
            ;;
         --namespace)
            [[ -z "${2:-}" ]] && _err "[jenkins] --namespace requires an argument"
            jenkins_namespace="$2"
            shift 2
            ;;
         --namespace=*)
            jenkins_namespace="${1#*=}"
            [[ -z "$jenkins_namespace" ]] && _err "[jenkins] --namespace requires a value"
            shift
            ;;
         --vault-namespace)
            [[ -z "${2:-}" ]] && _err "[jenkins] --vault-namespace requires an argument"
            vault_namespace="$2"
            shift 2
            ;;
         --vault-namespace=*)
            vault_namespace="${1#*=}"
            [[ -z "$vault_namespace" ]] && _err "[jenkins] --vault-namespace requires a value"
            shift
            ;;
         --vault-release)
            [[ -z "${2:-}" ]] && _err "[jenkins] --vault-release requires an argument"
            vault_release="$2"
            shift 2
            ;;
         --vault-release=*)
            vault_release="${1#*=}"
            [[ -z "$vault_release" ]] && _err "[jenkins] --vault-release requires a value"
            shift
            ;;
         --enable-ldap)
            enable_ldap=1
            shift
            ;;
         --enable-ad)
            enable_ad=1
            shift
            ;;
         --enable-ad-prod)
            enable_ad_prod=1
            shift
            ;;
         --skip-ad-validation)
            skip_ad_validation=1
            shift
            ;;
         --disable-ldap)
            enable_ldap=0
            enable_ad=0
            enable_ad_prod=0
            shift
            ;;
         --enable-vault)
            enable_vault=1
            shift
            ;;
         --disable-vault)
            enable_vault=0
            shift
            ;;
         --disable-mfa)
            enable_mfa=0
            shift
            ;;
         --)
            shift
            break
            ;;
         -*)
            _err "[jenkins] unknown option: $1"
            ;;
         *)
            # Positional arguments (backwards compatibility)
            if [[ -z "$jenkins_namespace" ]]; then
               jenkins_namespace="$1"
            elif [[ -z "$vault_namespace" ]]; then
               vault_namespace="$1"
            elif [[ -z "$vault_release" ]]; then
               vault_release="$1"
            else
               _err "[jenkins] unexpected argument: $1"
            fi
            shift
            ;;
      esac
   done

   # Apply defaults
   jenkins_namespace="${jenkins_namespace:-${JENKINS_NAMESPACE:-jenkins}}"
   vault_namespace="${vault_namespace:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   vault_release="${vault_release:-${VAULT_RELEASE:-$VAULT_RELEASE_DEFAULT}}"
   export JENKINS_NAMESPACE="$jenkins_namespace"

   local mode_count=$(( enable_ldap + enable_ad + enable_ad_prod ))
   if (( mode_count > 1 )); then
      _err "[jenkins] --enable-ldap, --enable-ad, and --enable-ad-prod are mutually exclusive"
   fi

   export JENKINS_LDAP_ENABLED="$enable_ldap"
   export JENKINS_AD_ENABLED="$enable_ad"
   export JENKINS_AD_PROD_ENABLED="$enable_ad_prod"
   export JENKINS_VAULT_ENABLED="$enable_vault"

   _jenkins_restore_trace "$restore_trace"

   _info "[jenkins] deploying to namespace: ${jenkins_namespace}"
   _jenkins_configure_leaf_host_defaults
   _jenkins_deploy_infra_prereqs "$enable_vault" "$enable_ad" "$enable_ldap" "$vault_namespace" "$vault_release"
   _create_jenkins_admin_vault_policy "$vault_namespace" "$vault_release"
   _create_jenkins_vault_ad_policy "$vault_namespace" "$vault_release" "$jenkins_namespace"
   _create_jenkins_vault_ldap_reader_role "$vault_namespace" "$vault_release" "$jenkins_namespace"
   _create_jenkins_cert_rotator_policy "$vault_namespace" "$vault_release" "" "" "$jenkins_namespace"
   _create_jenkins_namespace "$jenkins_namespace"
   _jenkins_ensure_secrets_ready "$vault_namespace" "$vault_release" "$jenkins_namespace" || return 1
   _create_jenkins_pv_pvc "$jenkins_namespace"
   _ensure_jenkins_cert "$vault_namespace" "$vault_release"
   _jenkins_deploy_with_retry "$jenkins_namespace" "$vault_namespace" "$vault_release" \
      "$enable_ldap" "$enable_ad" "$enable_ad_prod"
}

function _jenkins_select_template() {
   local ns="$1"
   local enable_ad_prod="$2"
   local enable_ad="$3"
   local enable_ldap="$4"
   local skip_ad_validation="$5"

   if (( enable_ad_prod )); then
      local ad_vars_file="$JENKINS_CONFIG_DIR/ad-vars.sh"
      if [[ -r "$ad_vars_file" ]]; then
         _info "[jenkins] sourcing AD configuration: $ad_vars_file"
         source "$ad_vars_file"
      else
         _warn "[jenkins] AD variables file not found: $ad_vars_file (using environment defaults)"
      fi
      if [[ -z "${AD_DOMAIN:-}" ]]; then
         _err "[jenkins] AD_DOMAIN must be set for production AD (e.g., export AD_DOMAIN=\"corp.example.com\")"
      fi
      if (( ! skip_ad_validation )); then
         _validate_ad_connectivity "$AD_DOMAIN" "${AD_SERVER:-}" "${AD_REQUIRE_TLS:-true}"
      else
         _warn "[jenkins] AD connectivity validation skipped (--skip-ad-validation)"
      fi
      _JENKINS_TEMPLATE_FILE="$JENKINS_CONFIG_DIR/values-ad-prod.yaml.tmpl"
      _JENKINS_AUTH_MODE="production-ad"
      _info "[jenkins] using production Active Directory template: values-ad-prod.yaml.tmpl"
      _info "[jenkins] AD domain: ${AD_DOMAIN}"
   elif (( enable_ad )); then
      local ad_test_vars_file="$SCRIPT_DIR/etc/ad/vars.sh"
      local ldap_vars_file="$SCRIPT_DIR/etc/ldap/vars.sh"
      if [[ -r "$ldap_vars_file" ]]; then
         _info "[jenkins] sourcing LDAP configuration: $ldap_vars_file"
         source "$ldap_vars_file"
      fi
      if [[ -r "$ad_test_vars_file" ]]; then
         _info "[jenkins] sourcing AD test configuration: $ad_test_vars_file"
         source "$ad_test_vars_file"
      fi
      export LDAP_URL="${LDAP_URL:-ldap://openldap-openldap-bitnami.identity.svc:1389}"
      export LDAP_BASE_DN="${LDAP_BASE_DN:-DC=corp,DC=example,DC=com}"
      export LDAP_BIND_DN="${LDAP_BIND_DN:-cn=admin,DC=corp,DC=example,DC=com}"
      export LDAP_USER_SEARCH_BASE="${LDAP_USER_SEARCH_BASE:-OU=Users,DC=corp,DC=example,DC=com}"
      export LDAP_GROUP_SEARCH_BASE="${LDAP_GROUP_SEARCH_BASE:-OU=Groups,DC=corp,DC=example,DC=com}"
      _JENKINS_TEMPLATE_FILE="$JENKINS_CONFIG_DIR/values-ad-test.yaml.tmpl"
      _JENKINS_AUTH_MODE="ad-testing"
      _info "[jenkins] using AD schema testing template: values-ad-test.yaml.tmpl"
   elif (( enable_ldap )); then
      local ldap_vars_file="$SCRIPT_DIR/etc/ldap/vars.sh"
      if [[ -r "$ldap_vars_file" ]]; then
         _info "[jenkins] sourcing LDAP configuration: $ldap_vars_file"
         source "$ldap_vars_file"
      fi
      export LDAP_URL="${LDAP_URL:-ldap://openldap-openldap-bitnami.identity.svc:1389}"
      _JENKINS_TEMPLATE_FILE="$JENKINS_CONFIG_DIR/values-ldap.yaml.tmpl"
      _JENKINS_AUTH_MODE="standard-ldap"
      _info "[jenkins] using standard LDAP template: values-ldap.yaml.tmpl"
   else
      _JENKINS_TEMPLATE_FILE="$JENKINS_CONFIG_DIR/values-default.yaml.tmpl"
      _JENKINS_AUTH_MODE="none"
      _info "[jenkins] using default template (no directory service): values-default.yaml.tmpl"
   fi
}

function _jenkins_load_ldap_secret() {
   local ns="$1"
   if _kubectl --no-exit get secret jenkins-ldap-config -n "$ns" >/dev/null 2>&1; then
      export LDAP_BASE_DN
      export LDAP_BIND_DN
      export LDAP_BIND_PASSWORD
      LDAP_BASE_DN=$(_kubectl get secret jenkins-ldap-config -n "$ns" -o jsonpath='{.data.LDAP_BASE_DN}' 2>/dev/null | base64 -d)
      LDAP_BIND_DN=$(_kubectl get secret jenkins-ldap-config -n "$ns" -o jsonpath='{.data.LDAP_BIND_DN}' 2>/dev/null | base64 -d)
      LDAP_BIND_PASSWORD=$(_kubectl get secret jenkins-ldap-config -n "$ns" -o jsonpath='{.data.LDAP_BIND_PASSWORD}' 2>/dev/null | base64 -d)
      if [[ -z "$LDAP_BIND_PASSWORD" ]]; then
         _warn "[jenkins] LDAP_BIND_PASSWORD is empty in jenkins-ldap-config secret"
      fi
      return 0
   fi
   _warn "[jenkins] jenkins-ldap-config secret not found, LDAP variables will be empty"
   return 1
}

function _jenkins_apply_istio_resources() {
   local ns="$1"
   local vault_pki_leaf_host="$2"
   local vault_pki_secret_name="$3"

   export VAULT_PKI_SECRET_NAME="$vault_pki_secret_name"
   export VAULT_PKI_LEAF_HOST="$vault_pki_leaf_host"

   local gw_template="$JENKINS_CONFIG_DIR/gateway.yaml"
   [[ -r "$gw_template" ]] || _err "Gateway YAML file not found: $gw_template"
   local gw_rendered
   gw_rendered=$(mktemp -t jenkins-gateway.XXXXXX.yaml)
   _jenkins_register_rendered_manifest "$gw_rendered"
   envsubst < "$gw_template" > "$gw_rendered"
   _kubectl apply -n istio-system --dry-run=client -f "$gw_rendered" || {
      local rc=$?
      _jenkins_cleanup_and_return "$rc"
      return "$rc"
   }
   _kubectl apply -n istio-system -f "$gw_rendered" || {
      local rc=$?
      _jenkins_cleanup_and_return "$rc"
      return "$rc"
   }

   local vs_template="$JENKINS_CONFIG_DIR/virtualservice.yaml.tmpl"
   [[ -r "$vs_template" ]] || _err "VirtualService template file not found: $vs_template"
   local dr_template="$JENKINS_CONFIG_DIR/destinationrule.yaml.tmpl"
   [[ -r "$dr_template" ]] || _err "DestinationRule template file not found: $dr_template"

   local vs_hosts_input="${JENKINS_VIRTUALSERVICE_HOSTS:-${VAULT_PKI_LEAF_HOST:-jenkins.dev.local.me}}"
   local -a vs_hosts_lines=()
   local -a _vs_hosts_split=()
   IFS=',' read -r -a _vs_hosts_split <<<"$vs_hosts_input"
   local _vs_host trimmed
   for _vs_host in "${_vs_hosts_split[@]}"; do
      trimmed="${_vs_host#"${_vs_host%%[![:space:]]*}"}"
      trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
      if [[ -n "$trimmed" ]]; then
         vs_hosts_lines+=("    - ${trimmed}")
      fi
   done
   (( ${#vs_hosts_lines[@]} )) || vs_hosts_lines=("    - jenkins.dev.local.me")
   local JENKINS_VIRTUALSERVICE_HOSTS_YAML
   printf -v JENKINS_VIRTUALSERVICE_HOSTS_YAML '%s\n' "${vs_hosts_lines[@]}"
   export JENKINS_VIRTUALSERVICE_HOSTS_YAML

   local vs_rendered
   vs_rendered=$(mktemp -t jenkins-virtualservice.XXXXXX.yaml)
   _jenkins_register_rendered_manifest "$vs_rendered"
   envsubst < "$vs_template" > "$vs_rendered"
   local dr_rendered
   dr_rendered=$(mktemp -t jenkins-destinationrule.XXXXXX.yaml)
   _jenkins_register_rendered_manifest "$dr_rendered"
   envsubst < "$dr_template" > "$dr_rendered"

   _kubectl apply -n "$ns" --dry-run=client -f "$vs_rendered" || {
      local rc=$?
      _jenkins_cleanup_and_return "$rc"
      return "$rc"
   }
   _kubectl apply -n "$ns" -f "$vs_rendered" || {
      local rc=$?
      _jenkins_cleanup_and_return "$rc"
      return "$rc"
   }
   _kubectl apply -n "$ns" --dry-run=client -f "$dr_rendered" || {
      local rc=$?
      _jenkins_cleanup_and_return "$rc"
      return "$rc"
   }
   _kubectl apply -n "$ns" -f "$dr_rendered" || {
      local rc=$?
      _jenkins_cleanup_and_return "$rc"
      return "$rc"
   }
}

function _jenkins_deploy_cert_rotator_if_enabled() {
   local ns="$1"
   local vault_namespace="$2"
   local vault_release="$3"

   if [[ "${JENKINS_CERT_ROTATOR_ENABLED:-0}" != "1" ]]; then
      return 0
   fi

   local rotator_template="$JENKINS_CONFIG_DIR/jenkins-cert-rotator.yaml.tmpl"
   local rotator_script="$JENKINS_CONFIG_DIR/cert-rotator.sh"
   local rotator_lib="$SCRIPT_DIR/lib/vault_pki.sh"
   [[ -r "$rotator_template" ]] || _err "Jenkins cert rotator template file not found: $rotator_template"
   [[ -r "$rotator_script" ]] || _err "Jenkins cert rotator script not found: $rotator_script"
   [[ -r "$rotator_lib" ]] || _err "Jenkins cert rotator Vault PKI helper not found: $rotator_lib"

   local rotator_script_b64 rotator_lib_b64
   rotator_script_b64=$(base64 < "$rotator_script" | tr -d '\n')
   [[ -n "$rotator_script_b64" ]] || _err "Failed to encode Jenkins cert rotator script"
   rotator_lib_b64=$(base64 < "$rotator_lib" | tr -d '\n')
   [[ -n "$rotator_lib_b64" ]] || _err "Failed to encode Jenkins cert rotator Vault PKI helper"

   export JENKINS_CERT_ROTATOR_SCRIPT_B64="$rotator_script_b64"
   export JENKINS_CERT_ROTATOR_VAULT_PKI_LIB_B64="$rotator_lib_b64"
   [[ -n "${JENKINS_CERT_ROTATOR_VAULT_ADDR:-}" ]] || \
      export JENKINS_CERT_ROTATOR_VAULT_ADDR="http://${vault_release}.${vault_namespace}.svc:8200"
   export VAULT_PKI_PATH="${VAULT_PKI_PATH:-pki}"
   export VAULT_PKI_ROLE_TTL="${VAULT_PKI_ROLE_TTL:-}"
   export VAULT_NAMESPACE="${VAULT_NAMESPACE:-}"
   export VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY:-}"
   export VAULT_CACERT="${VAULT_CACERT:-}"
   export JENKINS_CERT_ROTATOR_ALT_NAMES="${JENKINS_CERT_ROTATOR_ALT_NAMES:-}"

   local rotator_rendered
   rotator_rendered=$(mktemp -t jenkins-cert-rotator.XXXXXX.yaml)
   _jenkins_register_rendered_manifest "$rotator_rendered"
   local envsubst_vars='$JENKINS_CERT_ROTATOR_NAME $JENKINS_NAMESPACE $JENKINS_CERT_ROTATOR_SCRIPT_B64 $JENKINS_CERT_ROTATOR_VAULT_PKI_LIB_B64 $JENKINS_CERT_ROTATOR_SERVICE_ACCOUNT $VAULT_PKI_SECRET_NS $VAULT_PKI_SECRET_NAME $JENKINS_CERT_ROTATOR_SCHEDULE $JENKINS_CERT_ROTATOR_IMAGE $JENKINS_CERT_ROTATOR_VAULT_ADDR $VAULT_PKI_PATH $VAULT_PKI_ROLE $VAULT_PKI_ROLE_TTL $VAULT_PKI_LEAF_HOST $VAULT_NAMESPACE $VAULT_SKIP_VERIFY $VAULT_CACERT $JENKINS_CERT_ROTATOR_RENEW_BEFORE $JENKINS_CERT_ROTATOR_VAULT_ROLE $JENKINS_CERT_ROTATOR_ALT_NAMES'
   envsubst "$envsubst_vars" < "$rotator_template" > "$rotator_rendered"

   _kubectl apply --dry-run=client -f "$rotator_rendered" || {
      local rc=$?
      _jenkins_cleanup_and_return "$rc"
      return "$rc"
   }
   if _kubectl apply -f "$rotator_rendered"; then
      _jenkins_warn_on_cert_rotator_pull_failure "$ns"
   else
      local rc=$?
      _jenkins_cleanup_and_return "$rc"
      return "$rc"
   fi
}

function _jenkins_deploy_agent_resources() {
   local agent_rbac_template="$JENKINS_CONFIG_DIR/agent-rbac.yaml.tmpl"
   if [[ -r "$agent_rbac_template" ]]; then
      local agent_rbac_rendered
      agent_rbac_rendered=$(mktemp -t jenkins-agent-rbac.XXXXXX.yaml)
      _jenkins_register_rendered_manifest "$agent_rbac_rendered"
      envsubst < "$agent_rbac_template" > "$agent_rbac_rendered"
      if _kubectl apply -f "$agent_rbac_rendered"; then
         _info "[jenkins] ✓ Agent RBAC configured"
      else
         _warn "[jenkins] Failed to deploy agent RBAC (non-fatal)"
      fi
   else
      _info "[jenkins] Agent RBAC template not found (skipping)"
   fi

   _info "[jenkins] Agent service will be created automatically by Helm chart"

   local job_dsl_configmap_template="$JENKINS_CONFIG_DIR/job-dsl-configmap.yaml.tmpl"
   if [[ -r "$job_dsl_configmap_template" ]]; then
      local job_dsl_configmap_rendered
      job_dsl_configmap_rendered=$(mktemp -t jenkins-job-dsl-configmap.XXXXXX.yaml)
      _jenkins_register_rendered_manifest "$job_dsl_configmap_rendered"
      envsubst < "$job_dsl_configmap_template" > "$job_dsl_configmap_rendered"
      if _kubectl apply -f "$job_dsl_configmap_rendered"; then
         _info "[jenkins] ✓ Job DSL ConfigMap deployed"
      else
         _warn "[jenkins] Failed to deploy Job DSL ConfigMap (non-fatal)"
      fi
   else
      _info "[jenkins] Job DSL ConfigMap template not found (skipping)"
   fi
}

function _jenkins_run_helm_install() {
   local ns="$1"
   local values_file="$2"
   local helm_chart_ref="$3"
   local admin_secret="$4"

   local -a helm_args=(upgrade --install jenkins "$helm_chart_ref" --namespace "$ns" -f "$values_file")
   local helm_rc=0
   if ! _helm "${helm_args[@]}"; then
      helm_rc=$?
      if [[ "$admin_secret" == "jenkins" ]]; then
         if _jenkins_adopt_admin_secret "$ns" "$admin_secret" "jenkins"; then
            if _helm "${helm_args[@]}"; then
               helm_rc=0
            fi
         fi
      fi
   fi

   return "$helm_rc"
}

function _deploy_jenkins() {
   local ns="${1:-jenkins}"
   local vault_namespace="${2:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local vault_release="${3:-$VAULT_RELEASE_DEFAULT}"

   local helm_repo_url_default="https://charts.jenkins.io"
   local helm_repo_url="${JENKINS_HELM_REPO_URL:-$helm_repo_url_default}"
   local helm_chart_ref_default="jenkins/jenkins"
   local helm_chart_ref="${JENKINS_HELM_CHART_REF:-$helm_chart_ref_default}"
   local admin_secret="${JENKINS_ADMIN_SECRET_NAME:-jenkins}"

   local skip_repo_ops=0
   case "$helm_chart_ref" in
      /*|./*|../*|file://*)
         skip_repo_ops=1
         ;;
   esac
   case "$helm_repo_url" in
      ""|/*|./*|../*|file://*)
         skip_repo_ops=1
         ;;
   esac

   _JENKINS_RENDERED_MANIFESTS=()
   _jenkins_capture_trap_state EXIT _JENKINS_PREV_EXIT_TRAP_CMD _JENKINS_PREV_EXIT_TRAP_HANDLER
   _jenkins_capture_trap_state RETURN _JENKINS_PREV_RETURN_TRAP_CMD _JENKINS_PREV_RETURN_TRAP_HANDLER

   local exit_trap_cmd="_jenkins_cleanup_rendered_manifests EXIT"
   [[ -n "$_JENKINS_PREV_EXIT_TRAP_HANDLER" ]] && exit_trap_cmd+="; ${_JENKINS_PREV_EXIT_TRAP_HANDLER}"
   trap '$exit_trap_cmd' EXIT

   local return_trap_cmd="_jenkins_cleanup_rendered_manifests RETURN"
   [[ -n "$_JENKINS_PREV_RETURN_TRAP_HANDLER" ]] && return_trap_cmd+="; ${_JENKINS_PREV_RETURN_TRAP_HANDLER}"
   trap '$return_trap_cmd' RETURN

   if (( ! skip_repo_ops )); then
      _helm repo list 2>/dev/null | grep -q jenkins >/dev/null 2>&1 || _helm repo add jenkins "$helm_repo_url"
      _helm repo update
   fi

   _jenkins_select_template "$ns" "${enable_ad_prod:-0}" "${enable_ad:-0}" "${enable_ldap:-0}" "${skip_ad_validation:-0}"
   local template_file="$_JENKINS_TEMPLATE_FILE"
   local auth_mode="$_JENKINS_AUTH_MODE"

   case "$auth_mode" in
      standard-ldap|production-ad|ad-testing)
         _info "[jenkins] retrieving LDAP credentials from Kubernetes secret for template processing"
         _jenkins_load_ldap_secret "$ns" || true
         ;;
   esac

   # Process template with envsubst if it's a .tmpl file
   local values_file
   if [[ "$template_file" == *.tmpl ]]; then
      [[ -r "$template_file" ]] || _err "[jenkins] template file not found: $template_file"
      values_file=$(mktemp -t jenkins-values.XXXXXX.yaml)
      _jenkins_register_rendered_manifest "$values_file"
      # Export file reference variables for Vault agent sidecar
      # Use printf to avoid shell expansion of ${...} syntax
      printf -v LDAP_BIND_DN_FILE_REF '%s' '${file:/vault/secrets/ldap-bind-dn}'
      printf -v LDAP_BIND_PASSWORD_FILE_REF '%s' '${file:/vault/secrets/ldap-bind-password}'
      export LDAP_BIND_DN_FILE_REF LDAP_BIND_PASSWORD_FILE_REF
      # MFA plugin - enabled by default, use --disable-mfa to exclude
      if (( enable_mfa )); then
         export JENKINS_MFA_PLUGIN="- miniorange-two-factor"
      else
         export JENKINS_MFA_PLUGIN=""
      fi
      # Preserve admin credential placeholders so envsubst doesn't blank them
      if [[ -z "${JENKINS_ADMIN_USER:-}" ]]; then
         printf -v JENKINS_ADMIN_USER '%s' '${JENKINS_ADMIN_USER}'
      fi
      if [[ -z "${JENKINS_ADMIN_PASS:-}" ]]; then
         printf -v JENKINS_ADMIN_PASS '%s' '${JENKINS_ADMIN_PASS}'
      fi
      export JENKINS_ADMIN_USER JENKINS_ADMIN_PASS
      _info "[jenkins] processing template with envsubst: $template_file"
      envsubst < "$template_file" > "$values_file"
      _info "[jenkins] DEBUG rendered values (JENKINS_NAMESPACE) -> $(grep -n 'jenkins\.\${' "$values_file" || true)"
      _info "[jenkins] DEBUG rendered values snippet: $(grep -n 'jenkins\.' "$values_file" | head -n 3)"
   else
      values_file="${JENKINS_VALUES_FILE:-$template_file}"
      [[ -r "$values_file" ]] || _err "Jenkins values file not found: $values_file"
   fi

   # If LDAP is disabled, create a temporary values file without LDAP env vars
   if (( ! JENKINS_LDAP_ENABLED )); then
      local temp_values
      temp_values=$(mktemp -t jenkins-values.XXXXXX.yaml)
      _jenkins_register_rendered_manifest "$temp_values"

      local vault_leaf_host="${VAULT_PKI_LEAF_HOST:-jenkins.dev.local.me}"
      export VAULT_PKI_LEAF_HOST="$vault_leaf_host"

      awk -v leaf_host="$vault_leaf_host" '
      BEGIN {
         skip_depth = 0
         ldap_indent = 0
         in_jcasc_security = 0
         skip_security_realm = 0
         security_realm_indent = 0
         inserted_local_realm = 0
         skip_authz_block = 0
         auth_block_indent = 0
         in_env_block = 0
         env_block_indent = 0
         inserted_leaf_env = 0
      }

      /^[[:space:]]*01-security:/ {
         in_jcasc_security = 1
      }

      in_jcasc_security && /^[[:space:]]*[0-9][0-9]-/ && !/01-security/ {
         in_jcasc_security = 0
      }

      in_jcasc_security && /^[[:space:]]*securityRealm:/ {
         match($0, /^[[:space:]]*/ )
         security_realm_indent = RLENGTH
         indent_str = substr($0, 1, security_realm_indent)
         ;if (!inserted_local_realm) {
            print indent_str "securityRealm:"
            print indent_str "  local:"
            print indent_str "    allowsSignup: false"
            print indent_str "    users:"
            print indent_str "      - id: \"${JENKINS_ADMIN_USER}\""
            print indent_str "        password: \"${JENKINS_ADMIN_PASS}\""
            inserted_local_realm = 1
         }
         skip_security_realm = 1
         next
      }

      skip_security_realm {
         match($0, /^[[:space:]]*/ )
         current_indent = RLENGTH
         ;if (current_indent <= security_realm_indent && $0 ~ /^[[:space:]]*[a-zA-Z]+:/) {
            skip_security_realm = 0
         }
         ;if (skip_security_realm) next
      }

      in_jcasc_security && /^[[:space:]]*authorizationStrategy:/ {
         match($0, /^[[:space:]]*/ )
         auth_block_indent = RLENGTH
         indent_str = substr($0, 1, auth_block_indent)
         print indent_str "authorizationStrategy:"
         print indent_str "  projectMatrix:"
         print indent_str "    permissions:"
         print indent_str "      - \"Overall/Read:authenticated\""
         print indent_str "      - \"Overall/Read:${JENKINS_ADMIN_USER}\""
         print indent_str "      - \"Overall/Administer:${JENKINS_ADMIN_USER}\""
         skip_authz_block = 1
         next
      }

      skip_authz_block {
         match($0, /^[[:space:]]*/ )
         current_indent = RLENGTH
         ;if (current_indent <= auth_block_indent && $0 ~ /^[[:space:]]*([a-zA-Z#])/) {
            skip_authz_block = 0
         }
         ;if (skip_authz_block) next
      }

      /^[[:space:]]*containerEnv:/ {
         match($0, /^[[:space:]]*/ )
         env_block_indent = RLENGTH
         in_env_block = 1
         inserted_leaf_env = 0
      }

      /^[[:space:]]*- name: LDAP_/ {
         match($0, /^[[:space:]]*/ )
         ldap_indent = RLENGTH
         skip_depth = 1
         next
      }

      skip_depth > 0 {
         match($0, /^[[:space:]]*/ )
         current_indent = RLENGTH
         ;if ($0 ~ /^[[:space:]]*- name:/ && current_indent == ldap_indent) {
            skip_depth = 0
         } else if (current_indent <= ldap_indent && $0 !~ /^[[:space:]]*[a-zA-Z]+:/ && $0 !~ /^[[:space:]]*key:/) {
            skip_depth = 0
         }
         ;if (skip_depth > 0) next
      }

      {
         ;if (in_env_block && !inserted_leaf_env) {
            match($0, /^[[:space:]]*/ )
            current_indent = RLENGTH
            ;if (current_indent <= env_block_indent && $0 ~ /^[[:space:]]*([a-zA-Z#])/ && $0 !~ /^[[:space:]]*containerEnv:/) {
               printf "%s- name: VAULT_PKI_LEAF_HOST\n", sprintf("%*s", env_block_indent + 2, "")
               printf "%svalue: \"%s\"\n", sprintf("%*s", env_block_indent + 4, ""), leaf_host
               inserted_leaf_env = 1
               in_env_block = 0
            }
         }

         print
      }

      END {
         ;if (in_env_block && !inserted_leaf_env) {
            printf "%s- name: VAULT_PKI_LEAF_HOST\n", sprintf("%*s", env_block_indent + 2, "")
            printf "%svalue: \"%s\"\n", sprintf("%*s", env_block_indent + 4, ""), leaf_host
         }
      }
      ' "$values_file" > "$temp_values"

      values_file="$temp_values"
   fi

   _jenkins_run_helm_install "$ns" "$values_file" "$helm_chart_ref" "$admin_secret"
   local helm_rc=$?

   if (( helm_rc != 0 )); then
      _jenkins_cleanup_and_return "$helm_rc"
      return "$helm_rc"
   fi

   local vault_pki_secret_name="${VAULT_PKI_SECRET_NAME:-jenkins-tls}"
   local vault_pki_leaf_host="${VAULT_PKI_LEAF_HOST:-jenkins.dev.local.me}"

   export VAULT_PKI_SECRET_NAME="$vault_pki_secret_name"
   export VAULT_PKI_LEAF_HOST="$vault_pki_leaf_host"

   local vault_pki_secret_name="${VAULT_PKI_SECRET_NAME:-jenkins-tls}"
   local vault_pki_leaf_host="${VAULT_PKI_LEAF_HOST:-jenkins.dev.local.me}"

   export VAULT_PKI_SECRET_NAME="$vault_pki_secret_name"
   export VAULT_PKI_LEAF_HOST="$vault_pki_leaf_host"
   JENKINS_NAMESPACE="${ns:-${JENKINS_NAMESPACE}}"
   : "${JENKINS_NAMESPACE:?JENKINS_NAMESPACE not set}"

   _jenkins_apply_istio_resources "$ns" "$vault_pki_leaf_host" "$vault_pki_secret_name" || return $?
   _jenkins_deploy_cert_rotator_if_enabled "$ns" "$vault_namespace" "$vault_release" || return $?
   _jenkins_deploy_agent_resources

   local jenkins_host="$vault_pki_leaf_host"
   local secret_namespace="${VAULT_PKI_SECRET_NS:-istio-system}"
   local secret_name="$vault_pki_secret_name"
   if [[ "${JENKINS_SKIP_TLS:-0}" != "1" ]]; then
      _vault_issue_pki_tls_secret "$vault_namespace" "$vault_release" "" "" \
         "$jenkins_host" "$secret_namespace" "$secret_name"
      local rc=$?
   else
      local rc=0
   fi
   _jenkins_cleanup_and_return "$rc"
   return "$rc"
}

function _wait_for_jenkins_ready() {
   local ns="$1"
   local timeout_arg="${2:-}"
   local timeout

   if [[ -n "$timeout_arg" ]]; then
      timeout="$timeout_arg"
   elif [[ -n "${JENKINS_READY_TIMEOUT:-}" ]]; then
      timeout="$JENKINS_READY_TIMEOUT"
   else
      timeout="10m"
   fi

   local total_seconds
   case "$timeout" in
      *m) total_seconds=$(( ${timeout%m} * 60 )) ;;
      *s) total_seconds=${timeout%s} ;;
      *) total_seconds=$timeout ;;
   esac
   local end=$((SECONDS + total_seconds))
   local wait_count=0
   local last_status=""

   # First check if pod exists
   local pod_exists=0
   local pod_check_timeout=$((SECONDS + 60))
   while (( SECONDS < pod_check_timeout )); do
      if _kubectl --no-exit --quiet -n "$ns" get pod -l app.kubernetes.io/component=jenkins-controller >/dev/null 2>&1; then
         pod_exists=1
         break
      fi
      echo "Waiting for Jenkins controller pod to be created..."
      sleep 3
   done

   if (( ! pod_exists )); then
      echo "Jenkins controller pod was not created within 60 seconds" >&2
      return 1
   fi

   # Wait for pod to be ready with progress updates
   until _kubectl --no-exit --quiet -n "$ns" wait \
      --for=condition=Ready \
      pod -l app.kubernetes.io/component=jenkins-controller \
      --timeout=10s >/dev/null 2>&1; do

      wait_count=$((wait_count + 1))

      # Get current pod status for informative message
      local current_status
      current_status=$(_kubectl --no-exit --quiet -n "$ns" get pod -l app.kubernetes.io/component=jenkins-controller \
         -o jsonpath='{.items[0].status.containerStatuses[*].ready}' 2>/dev/null || echo "unknown")

      # Only print message if status changed or every 12 iterations (1 minute)
      if [[ "$current_status" != "$last_status" ]] || (( wait_count % 12 == 0 )); then
         local elapsed=$((SECONDS - (end - total_seconds)))
         echo "Waiting for Jenkins controller pod to be ready... (${elapsed}s elapsed, status: ${current_status})"
         last_status="$current_status"
      fi

      if (( SECONDS >= end )); then
         echo "Timed out after ${total_seconds}s waiting for Jenkins controller pod to be ready" >&2
         echo "Last known status: ${current_status}" >&2
         _kubectl -n "$ns" get pod -l app.kubernetes.io/component=jenkins-controller >&2 || true
         _kubectl -n "$ns" describe pod -l app.kubernetes.io/component=jenkins-controller >&2 || true
         return 1
      fi
      sleep 5
   done

   echo "Jenkins controller pod is ready"
}

function _create_jenkins_admin_vault_policy() {
   local vault_namespace="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local vault_release="${2:-$VAULT_RELEASE_DEFAULT}"

   _vault_login "$vault_namespace" "$vault_release"

   local policy_exists=0
   if _vault_policy_exists "$vault_namespace" "$vault_release" "jenkins-admin"; then
      policy_exists=1
   fi

   if (( ! policy_exists )); then
      local policy_content
      policy_content=$(cat <<'HCL'
length = 24
rule "charset" { charset = "abcdefghijklmnopqrstuvwxyz" }
rule "charset" { charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ" }
rule "charset" { charset = "0123456789" }
rule "charset" { charset = "!@#$%^&*()-_=+[]{};:,.?" }
HCL
)
      echo "$policy_content" | tee jenkins-admin.hcl | \
         _vault_exec "$vault_namespace" "vault write sys/policies/password/jenkins-admin policy=-" "$vault_release"
      rm -f jenkins-admin.hcl
   fi

   local mount_path="${JENKINS_VAULT_KV_MOUNT:-secret}"
   local secret_path="${JENKINS_ADMIN_VAULT_PATH:-eso/jenkins-admin}"

   # Use secret backend interface if available, otherwise fallback to direct Vault commands
   if declare -f secret_backend_init >/dev/null 2>&1; then
      # New secret backend interface
      export VAULT_SECRET_BACKEND_NS="$vault_namespace"
      export VAULT_SECRET_BACKEND_RELEASE="$vault_release"
      export VAULT_SECRET_BACKEND_MOUNT="$mount_path"

      secret_backend_init

      if secret_backend_exists "$secret_path"; then
         _info "[jenkins] Secret ${secret_path} already exists; skipping seed"
         return 0
      fi

      local jenkins_admin_pass
      jenkins_admin_pass=$(_vault_exec "$vault_namespace" \
         "vault read -field=password sys/policies/password/jenkins-admin/generate" "$vault_release")

      # Note: secret_backend_put handles password masking internally
      if ! secret_backend_put "$secret_path" username=jenkins-admin password="$jenkins_admin_pass"; then
         # Error already logged by secret_backend_put with password masked
         return 1
      fi
   else
      # Fallback to direct Vault commands (for backward compatibility)
      if _vault_exec --no-exit "$vault_namespace" "vault kv get ${mount_path}/${secret_path}" "$vault_release" >/dev/null 2>&1; then
         _info "[jenkins] Vault secret ${mount_path}/${secret_path} already exists; skipping seed"
         return 0
      fi

      local script_content
      script_content=$(cat <<SCRIPT
set -euo pipefail
jenkins_admin_pass=\$(vault read -field=password sys/policies/password/jenkins-admin/generate)
vault kv put ${mount_path}/${secret_path} username=jenkins-admin password="\$jenkins_admin_pass"
SCRIPT
)
      echo "$script_content" | _no_trace _vault_exec "$vault_namespace" "sh -" "$vault_release"
   fi
}

function _sync_vault_jenkins_admin() {
   local vault_namespace="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local vault_release="${2:-$VAULT_RELEASE_DEFAULT}"
   local jenkins_namespace="${3:-jenkins}"

   _vault_exec "$vault_namespace" "vault write -field=password sys/policies/password/jenkins-admin/generate" "$vault_release"

   local script_content
   script_content=$(cat <<'SCRIPT'
jenkins_admin_pass=$(vault read -field=password sys/policies/password/jenkins-admin/generate)
vault kv put secret/eso/jenkins-admin username=jenkins-admin password="$jenkins_admin_pass"
SCRIPT
)
   echo "$script_content" | _vault_exec "$vault_namespace" "sh -" "$vault_release"
}

function _create_jenkins_vault_ldap_reader_role() {
   local vault_namespace="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local vault_release="${2:-$VAULT_RELEASE_DEFAULT}"
   local jenkins_namespace="${3:-jenkins}"
   local role_name="jenkins-ldap-reader"
   local policy_name="jenkins-ldap-reader"

   _info "[jenkins] configuring Vault LDAP reader policy and role for vault-agent sidecar"

   _vault_login "$vault_namespace" "$vault_release"

   # Create policy if it doesn't exist
   if ! _vault_policy_exists "$vault_namespace" "$vault_release" "$policy_name"; then
      local ldap_read_policy
      ldap_read_policy=$(cat <<'HCL'
path "secret/data/ldap/openldap-admin" {
  capabilities = ["read"]
}
HCL
)
      echo "$ldap_read_policy" | _vault_exec "$vault_namespace" "vault policy write $policy_name -" "$vault_release" || \
         _err "Failed to create Vault policy $policy_name"
   fi

   # Create or update Kubernetes auth role
   _vault_exec "$vault_namespace" \
      "vault write auth/kubernetes/role/$role_name bound_service_account_names=jenkins bound_service_account_namespaces=$jenkins_namespace policies=$policy_name ttl=1h" \
      "$vault_release"
}

function _create_jenkins_vault_ad_policy() {
   local vault_namespace="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local vault_release="${2:-$VAULT_RELEASE_DEFAULT}"
   local jenkins_namespace="${3:-jenkins}"

   _vault_login "$vault_namespace" "$vault_release"

   if ! _vault_policy_exists "$vault_namespace" "$vault_release" "jenkins-jcasc-read"; then
      local read_policy
      read_policy=$(cat <<'HCL'
path "secret/data/jenkins/ad-ldap"     { capabilities = ["read"] }
path "secret/data/jenkins/ad-adreader" { capabilities = ["read"] }
HCL
)
      echo "$read_policy" | _vault_exec "$vault_namespace" "vault policy write jenkins-jcasc-read -" "$vault_release"

      _vault_exec "$vault_namespace" \
         "vault write auth/kubernetes/role/jenkins-jcasc-reader bound_service_account_names=jenkins bound_service_account_namespaces=$jenkins_namespace policies=jenkins-jcasc-read ttl=30m" \
         "$vault_release"
   fi

   if ! _vault_policy_exists "$vault_namespace" "$vault_release" "jenkins-jcasc-write"; then
      local write_policy
      write_policy=$(cat <<'HCL'
path "secret/data/jenkins/ad-ldap"     { capabilities = ["create", "update"] }
path "secret/data/jenkins/ad-adreader" { capabilities = ["create", "update"] }
HCL
)
      echo "$write_policy" | _vault_exec "$vault_namespace" "vault policy write jenkins-jcasc-write -" "$vault_release"

      _vault_exec "$vault_namespace" \
         "vault write auth/kubernetes/role/jenkins-jcasc-writer bound_service_account_names=jenkins bound_service_account_namespaces=$jenkins_namespace policies=jenkins-jcasc-write ttl=15m" \
         "$vault_release"
   fi
}

function _create_jenkins_cert_rotator_policy() {
   local vault_namespace="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local vault_release="${2:-$VAULT_RELEASE_DEFAULT}"
   local pki_path="${3:-${VAULT_PKI_PATH:-pki}}"
   local pki_role="${4:-${VAULT_PKI_ROLE:-jenkins-tls}}"
   local jenkins_namespace="${5:-jenkins}"
   local rotator_service_account="${6:-jenkins-cert-rotator}"
   local policy_name="jenkins-cert-rotator"

   _info "[jenkins] configuring Vault cert-rotator policy and role"

   _vault_login "$vault_namespace" "$vault_release"

   local ensure_policy=1

   if _vault_policy_exists "$vault_namespace" "$vault_release" "$policy_name"; then
      local current_policy=""
      current_policy=$(_vault_exec --no-exit "$vault_namespace" \
         "vault policy read $policy_name" "$vault_release" 2>/dev/null || true)

      if [[ "$current_policy" == *"path \"${pki_path}/revoke\""* ]]; then
         ensure_policy=0
      fi
   fi

   if (( ensure_policy )); then
      local policy_file
      policy_file=$(mktemp -t jenkins-cert-rotator-policy.XXXXXX.hcl)
      cat > "$policy_file" <<HCL
path "${pki_path}/issue/${pki_role}" {
   capabilities = ["update"]
}
path "${pki_path}/revoke" {
   capabilities = ["update"]
}
path "${pki_path}/roles/${pki_role}" {
   capabilities = ["read"]
}
path "${pki_path}/cert/ca" {
   capabilities = ["read"]
}
path "${pki_path}/ca/pem" {
   capabilities = ["read"]
}
HCL

      # Copy policy file to vault pod and apply it
      local vault_pod="${vault_release}-0"
      _kubectl cp "$policy_file" "${vault_namespace}/${vault_pod}:/tmp/jenkins-cert-rotator-policy.hcl" 2>/dev/null || \
         _err "Failed to copy policy file to Vault pod"

      _vault_exec "$vault_namespace" "vault policy write $policy_name /tmp/jenkins-cert-rotator-policy.hcl" "$vault_release" || \
         _err "Failed to create Vault policy $policy_name"

      rm -f "$policy_file"
   fi

      _vault_exec "$vault_namespace" \
      "vault write auth/kubernetes/role/jenkins-cert-rotator bound_service_account_names=$rotator_service_account bound_service_account_namespaces=$jenkins_namespace policies=$policy_name ttl=24h" \
      "$vault_release"
}
