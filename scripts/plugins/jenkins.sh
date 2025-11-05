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

   local -a trap_args=("$@")
   local -a saved_tokens=()
   if [[ -n "${!handler_var:-}" ]]; then
      eval "saved_tokens=( ${!handler_var} )"
   fi
   local skip_count=0
   if (( ${#saved_tokens[@]} > 1 )); then
      skip_count=$(( ${#saved_tokens[@]} - 1 ))
   fi
   if (( skip_count > 0 )); then
      if (( ${#trap_args[@]} > skip_count )); then
         trap_args=("${trap_args[@]:${skip_count}}")
      else
         trap_args=()
      fi
   else
      while (( ${#trap_args[@]} )); do
         case "${trap_args[0]}" in
            "$signal"|_JENKINS_PREV_*)
               trap_args=("${trap_args[@]:1}")
               ;;
            *)
               break
               ;;
         esac
      done
   fi
   if (( ${#trap_args[@]} )); then
      local total=${#trap_args[@]}
      if (( total % 2 == 0 )); then
         local half=$(( total / 2 ))
         local duplicate=1
         local i
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
      local failure_reason="" failure_message="" failure_details=""
      local IFS=$'\t'
      read -r failure_reason failure_message <<< "$failure_fields"
      if [[ -n "$failure_reason" ]]; then
         failure_details="$failure_reason"
      fi
      if [[ -n "$failure_message" ]]; then
         if [[ -n "$failure_details" ]]; then
            failure_details+="; $failure_message"
         else
            failure_details="$failure_message"
         fi
      fi
      if [[ -z "$failure_details" ]]; then
         failure_details="image pull failure"
      fi
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
   if ! deploy_ldap "$ldap_ns" "$ldap_release"; then
      _err "[jenkins] LDAP deployment failed"
   fi

   # Seed Jenkins service account in Vault LDAP
   if declare -f _vault_seed_ldap_service_accounts >/dev/null 2>&1; then
      _info "[jenkins] seeding Jenkins LDAP service account in Vault"
      _vault_seed_ldap_service_accounts "$vault_ns" "$vault_release"
   else
      _warn "[jenkins] _vault_seed_ldap_service_accounts not available; skipping service account seed"
   fi
}

function deploy_jenkins() {
   local jenkins_namespace=""
   local vault_namespace=""
   local vault_release=""
   local enable_ldap="${JENKINS_LDAP_ENABLED:-1}"
   local enable_vault="${JENKINS_VAULT_ENABLED:-1}"
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
  --enable-ldap              Deploy LDAP integration (default: disabled)
  --disable-ldap             Skip LDAP deployment
  --enable-vault             Deploy Vault (default: disabled)
  --disable-vault            Skip Vault deployment (use existing)
  -h, --help                 Show this help message

Feature Flags (environment variables):
  JENKINS_LDAP_ENABLED=0|1   Enable LDAP auto-deployment (default: 0)
  JENKINS_VAULT_ENABLED=0|1  Enable Vault auto-deployment (default: 0)

Examples:
  # Show this help message
  deploy_jenkins

  # Minimal deployment (Jenkins only, no LDAP, no Vault)
  deploy_jenkins --disable-ldap --disable-vault

  # Full deployment with all integrations
  deploy_jenkins --enable-ldap --enable-vault

  # Deploy with LDAP integration only
  deploy_jenkins --enable-ldap

  # Deploy with Vault integration only
  deploy_jenkins --enable-vault

  # Deploy to custom namespace with full stack
  deploy_jenkins --namespace jenkins-prod --enable-ldap --enable-vault

Positional arguments (backwards compatible):
  deploy_jenkins [namespace] [vault-namespace] [vault-release]
EOF
      if (( restore_trace )); then set -x; fi
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
  --enable-ldap              Deploy LDAP integration (default: disabled)
  --disable-ldap             Skip LDAP deployment
  --enable-vault             Deploy Vault (default: disabled)
  --disable-vault            Skip Vault deployment (use existing)
  -h, --help                 Show this help message

Feature Flags (environment variables):
  JENKINS_LDAP_ENABLED=0|1   Enable LDAP auto-deployment (default: 0)
  JENKINS_VAULT_ENABLED=0|1  Enable Vault auto-deployment (default: 0)

Examples:
  # Minimal deployment (Jenkins only, no LDAP, no Vault)
  deploy_jenkins

  # Full deployment with all integrations
  deploy_jenkins --enable-ldap --enable-vault

  # Deploy with LDAP integration only
  deploy_jenkins --enable-ldap

  # Deploy with Vault integration only
  deploy_jenkins --enable-vault

  # Deploy to custom namespace with full stack
  deploy_jenkins --namespace jenkins-prod --enable-ldap --enable-vault

Positional arguments (backwards compatible):
  deploy_jenkins [namespace] [vault-namespace] [vault-release]
EOF
            if (( restore_trace )); then set -x; fi
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
         --disable-ldap)
            enable_ldap=0
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
   jenkins_namespace="${jenkins_namespace:-jenkins}"
   vault_namespace="${vault_namespace:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   vault_release="${vault_release:-${VAULT_RELEASE:-$VAULT_RELEASE_DEFAULT}}"

   # Export enable flags so downstream functions can check them
   export JENKINS_LDAP_ENABLED="$enable_ldap"
   export JENKINS_VAULT_ENABLED="$enable_vault"

   if (( restore_trace )); then set -x; fi

   _info "[jenkins] deploying to namespace: ${jenkins_namespace}"
   _info "[jenkins] LDAP integration: $( (( enable_ldap )) && echo "enabled" || echo "disabled" )"
   _info "[jenkins] Vault deployment: $( (( enable_vault )) && echo "enabled" || echo "disabled" )"

   _jenkins_configure_leaf_host_defaults

   # Deploy ESO only if Vault is enabled (ESO requires Vault as backend)
   if (( enable_vault )); then
      deploy_eso
   fi

   # Deploy Vault if enabled
   if (( enable_vault )); then
      _info "[jenkins] deploying Vault to ${vault_namespace}/${vault_release}"
      deploy_vault "$vault_namespace" "$vault_release"
   else
      _info "[jenkins] skipping Vault deployment (using existing instance)"
   fi

   # Deploy LDAP if enabled
   if (( enable_ldap )); then
      _deploy_jenkins_ldap "$vault_namespace" "$vault_release"
   else
      _info "[jenkins] skipping LDAP deployment"
   fi
   _create_jenkins_admin_vault_policy "$vault_namespace" "$vault_release"
   _create_jenkins_vault_ad_policy "$vault_namespace" "$vault_release" "$jenkins_namespace"
   _create_jenkins_cert_rotator_policy "$vault_namespace" "$vault_release" "" "" "$jenkins_namespace"
   _create_jenkins_namespace "$jenkins_namespace"
   local -a _jenkins_secret_prefixes=()
   if [[ -n "${JENKINS_VAULT_POLICY_PREFIX:-}" ]]; then
      local _configured_prefixes="${JENKINS_VAULT_POLICY_PREFIX//,/ }"
      local -a _configured_array=()
      read -r -a _configured_array <<< "$_configured_prefixes"
      _jenkins_secret_prefixes+=("${_configured_array[@]}")
   fi

   local -a _jenkins_secret_paths=(
      "${JENKINS_ADMIN_VAULT_PATH:-}"
      "${JENKINS_LDAP_VAULT_PATH:-}"
   )

   local prefix
   for prefix in "${_jenkins_secret_paths[@]}"; do
      [[ -z "$prefix" ]] && continue
      _jenkins_secret_prefixes+=("$prefix")
   done

   local -a _jenkins_unique_prefixes=()
   for prefix in "${_jenkins_secret_prefixes[@]}"; do
      [[ -z "$prefix" ]] && continue
      local trimmed="${prefix#/}"
      trimmed="${trimmed%/}"
      [[ -z "$trimmed" ]] && continue
      local seen=0 existing
      for existing in "${_jenkins_unique_prefixes[@]}"; do
         if [[ "$existing" == "$trimmed" ]]; then
            seen=1
            break
         fi
      done
      (( seen )) && continue
      _jenkins_unique_prefixes+=("$trimmed")
   done

   local _jenkins_prefix_arg=""
   for prefix in "${_jenkins_unique_prefixes[@]}"; do
      if [[ -n "$_jenkins_prefix_arg" ]]; then
         _jenkins_prefix_arg+=","
      fi
      _jenkins_prefix_arg+="$prefix"
   done

   if ! _vault_configure_secret_reader_role \
         "$vault_namespace" \
         "$vault_release" \
         "$JENKINS_ESO_SERVICE_ACCOUNT" \
         "$jenkins_namespace" \
         "$JENKINS_VAULT_KV_MOUNT" \
         "$_jenkins_prefix_arg" \
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
   # Only wait for LDAP secret if LDAP is enabled
   if (( JENKINS_LDAP_ENABLED )); then
      if ! _jenkins_wait_for_secret "$jenkins_namespace" "$JENKINS_LDAP_SECRET_NAME"; then
         _err "[jenkins] Vault-sourced secret ${JENKINS_LDAP_SECRET_NAME} not available"
         return 1
      fi
   fi
   _create_jenkins_pv_pvc "$jenkins_namespace"
   _ensure_jenkins_cert "$vault_namespace" "$vault_release"

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
   if [[ -n "$_JENKINS_PREV_EXIT_TRAP_HANDLER" ]]; then
      exit_trap_cmd+="; ${_JENKINS_PREV_EXIT_TRAP_HANDLER}"
   fi
   trap '$exit_trap_cmd' EXIT

   local return_trap_cmd="_jenkins_cleanup_rendered_manifests RETURN"
   if [[ -n "$_JENKINS_PREV_RETURN_TRAP_HANDLER" ]]; then
      return_trap_cmd+="; ${_JENKINS_PREV_RETURN_TRAP_HANDLER}"
   fi
   trap '$return_trap_cmd' RETURN

   if (( ! skip_repo_ops )); then
     if ! _helm repo list 2>/dev/null | grep -q jenkins; then
       _helm repo add jenkins "$helm_repo_url"
     fi
     _helm repo update
   fi
   local values_file="${JENKINS_VALUES_FILE:-$JENKINS_CONFIG_DIR/values.yaml}"
   if [[ ! -r "$values_file" ]]; then
      _err "Jenkins values file not found: $values_file"
   fi

   # If LDAP is disabled, create a temporary values file without LDAP env vars
   if (( ! JENKINS_LDAP_ENABLED )); then
      local temp_values
      temp_values=$(mktemp -t jenkins-values.XXXXXX.yaml)
      _jenkins_register_rendered_manifest "$temp_values"

      # Remove LDAP-related environment variables and JCasC security realm using awk
      # This removes:
      # 1. LDAP env var blocks (name + value/valueFrom) from containerEnv
      # 2. LDAP securityRealm block from JCasC configScripts
      awk '
      BEGIN {
         skip_depth = 0
         current_indent = 0
         ldap_indent = 0
         in_jcasc_security = 0
         skip_security_realm = 0
         security_realm_indent = 0
      }

      # Track when we are in the 01-security JCasC config
      /^[[:space:]]*01-security:/ {
         in_jcasc_security = 1
      }

      # End of 01-security section (next config or end of JCasC)
      in_jcasc_security && /^[[:space:]]*[0-9][0-9]-/ && !/01-security/ {
         in_jcasc_security = 0
      }

      # When in JCasC security config, detect LDAP securityRealm block
      in_jcasc_security && /^[[:space:]]*securityRealm:/ {
         match($0, /^[[:space:]]*/)
         security_realm_indent = RLENGTH
         skip_security_realm = 1
         next
      }

      # Skip entire securityRealm block (including nested ldap config)
      skip_security_realm {
         match($0, /^[[:space:]]*/)
         current_indent = RLENGTH

         # Stop skipping when we hit a sibling key at same or less indent as securityRealm
         if (current_indent <= security_realm_indent && $0 ~ /^[[:space:]]*[a-zA-Z]+:/) {
            skip_security_realm = 0
         }

         if (skip_security_realm) next
      }

      # When we find an LDAP env var, mark its indent level and start skipping
      /^[[:space:]]*- name: LDAP_/ {
         match($0, /^[[:space:]]*/)
         ldap_indent = RLENGTH
         skip_depth = 1
         next
      }

      # If skipping env var, check indent to know when the LDAP block ends
      skip_depth > 0 {
         match($0, /^[[:space:]]*/)
         current_indent = RLENGTH

         # If we hit another "- name:" at the same level, stop skipping
         if ($0 ~ /^[[:space:]]*- name:/ && current_indent == ldap_indent) {
            skip_depth = 0
         }
         # If we hit a line with less or equal indent that is not a continuation, stop skipping
         else if (current_indent <= ldap_indent && $0 !~ /^[[:space:]]*[a-zA-Z]+:/ && $0 !~ /^[[:space:]]*key:/) {
            skip_depth = 0
         }

         if (skip_depth > 0) next
      }

      # Print non-skipped lines
      { print }
      ' "$values_file" > "$temp_values"

      values_file="$temp_values"
   fi

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

   if (( helm_rc != 0 )); then
      _jenkins_cleanup_and_return "$helm_rc"
      return "$helm_rc"
   fi

   local vault_pki_secret_name="${VAULT_PKI_SECRET_NAME:-jenkins-tls}"
   local vault_pki_leaf_host="${VAULT_PKI_LEAF_HOST:-jenkins.dev.local.me}"

   export VAULT_PKI_SECRET_NAME="$vault_pki_secret_name"
   export VAULT_PKI_LEAF_HOST="$vault_pki_leaf_host"

   local gw_template="$JENKINS_CONFIG_DIR/gateway.yaml"
   if [[ ! -r "$gw_template" ]]; then
      _err "Gateway YAML file not found: $gw_template"
   fi

   local gw_rendered
   gw_rendered=$(mktemp -t jenkins-gateway.XXXXXX.yaml)
   _jenkins_register_rendered_manifest "$gw_rendered"
   envsubst < "$gw_template" > "$gw_rendered"

   if _kubectl apply -n istio-system --dry-run=client -f "$gw_rendered"; then
      :
   else
      local rc=$?
      _jenkins_cleanup_and_return "$rc"
      return "$rc"
   fi
   if _kubectl apply -n istio-system -f "$gw_rendered"; then
      :
   else
      local rc=$?
      _jenkins_cleanup_and_return "$rc"
      return "$rc"
   fi

   JENKINS_NAMESPACE="${ns:-${JENKINS_NAMESPACE}}"
   : "${JENKINS_NAMESPACE:?JENKINS_NAMESPACE not set}"
   local vs_template="$JENKINS_CONFIG_DIR/virtualservice.yaml.tmpl"
   if [[ ! -r "$vs_template" ]]; then
      _err "VirtualService template file not found: $vs_template"
   fi

   local dr_template="$JENKINS_CONFIG_DIR/destinationrule.yaml.tmpl"
   if [[ ! -r "$dr_template" ]]; then
      _err "DestinationRule template file not found: $dr_template"
   fi

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
   if (( ${#vs_hosts_lines[@]} == 0 )); then
      vs_hosts_lines=("    - jenkins.dev.local.me")
   fi
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

   if _kubectl apply -n "$ns" --dry-run=client -f "$vs_rendered"; then
      :
   else
      local rc=$?
      _jenkins_cleanup_and_return "$rc"
      return "$rc"
   fi
   if _kubectl apply -n "$ns" -f "$vs_rendered"; then
      :
   else
      local rc=$?
      _jenkins_cleanup_and_return "$rc"
      return "$rc"
   fi

   if _kubectl apply -n "$ns" --dry-run=client -f "$dr_rendered"; then
      :
   else
      local rc=$?
      _jenkins_cleanup_and_return "$rc"
      return "$rc"
   fi
   if _kubectl apply -n "$ns" -f "$dr_rendered"; then
      :
   else
      local rc=$?
      _jenkins_cleanup_and_return "$rc"
      return "$rc"
   fi

   if [[ "${JENKINS_CERT_ROTATOR_ENABLED:-0}" == "1" ]]; then
      local rotator_template="$JENKINS_CONFIG_DIR/jenkins-cert-rotator.yaml.tmpl"
      local rotator_script="$JENKINS_CONFIG_DIR/cert-rotator.sh"
      local rotator_lib="$SCRIPT_DIR/lib/vault_pki.sh"

      if [[ ! -r "$rotator_template" ]]; then
         _err "Jenkins cert rotator template file not found: $rotator_template"
      fi

      if [[ ! -r "$rotator_script" ]]; then
         _err "Jenkins cert rotator script not found: $rotator_script"
      fi

      if [[ ! -r "$rotator_lib" ]]; then
         _err "Jenkins cert rotator Vault PKI helper not found: $rotator_lib"
      fi

      local rotator_script_b64 rotator_lib_b64
      rotator_script_b64=$(base64 < "$rotator_script" | tr -d '\n')

      if [[ -z "$rotator_script_b64" ]]; then
         _err "Failed to encode Jenkins cert rotator script"
      fi

      rotator_lib_b64=$(base64 < "$rotator_lib" | tr -d '\n')

      if [[ -z "$rotator_lib_b64" ]]; then
         _err "Failed to encode Jenkins cert rotator Vault PKI helper"
      fi

      export JENKINS_CERT_ROTATOR_SCRIPT_B64="$rotator_script_b64"
      export JENKINS_CERT_ROTATOR_VAULT_PKI_LIB_B64="$rotator_lib_b64"

      if [[ -z "${JENKINS_CERT_ROTATOR_VAULT_ADDR:-}" ]]; then
         export JENKINS_CERT_ROTATOR_VAULT_ADDR="http://${vault_release}.${vault_namespace}.svc:8200"
      fi

      local rotator_rendered
      rotator_rendered=$(mktemp -t jenkins-cert-rotator.XXXXXX.yaml)
      _jenkins_register_rendered_manifest "$rotator_rendered"
      envsubst < "$rotator_template" > "$rotator_rendered"

      if _kubectl apply --dry-run=client -f "$rotator_rendered"; then
         :
      else
         local rc=$?
         _jenkins_cleanup_and_return "$rc"
         return "$rc"
      fi

      if _kubectl apply -f "$rotator_rendered"; then
         _jenkins_warn_on_cert_rotator_pull_failure "$ns"
      else
         local rc=$?
         _jenkins_cleanup_and_return "$rc"
         return "$rc"
      fi
   fi

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
      timeout="5m"
   fi

   local total_seconds
   case "$timeout" in
      *m) total_seconds=$(( ${timeout%m} * 60 )) ;;
      *s) total_seconds=${timeout%s} ;;
      *) total_seconds=$timeout ;;
   esac
   local end=$((SECONDS + total_seconds))

   until _kubectl --no-exit --quiet -n "$ns" wait \
      --for=condition=Ready \
      pod -l app.kubernetes.io/component=jenkins-controller \
      --timeout=5s >/dev/null 2>&1; do
      echo "Waiting for Jenkins controller pod to be ready..."
      if (( SECONDS >= end )); then
         echo "Timed out waiting for Jenkins controller pod to be ready" >&2
         return 1
      fi
      sleep 5
   done
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

      if ! secret_backend_put "$secret_path" username=jenkins-admin password="$jenkins_admin_pass"; then
         _err "[jenkins] failed to seed admin secret at $secret_path"
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
      local policy_content
      policy_content=$(cat <<HCL
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
)
      echo "$policy_content" | _vault_exec "$vault_namespace" "vault policy write $policy_name -" "$vault_release"
   fi

   _vault_exec "$vault_namespace" \
      "vault write auth/kubernetes/role/jenkins-cert-rotator bound_service_account_names=$rotator_service_account bound_service_account_namespaces=$jenkins_namespace policies=$policy_name ttl=24h" \
      "$vault_release"
}
