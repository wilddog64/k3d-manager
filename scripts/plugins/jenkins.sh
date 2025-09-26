VAULT_PLUGIN="$PLUGINS_DIR/vault.sh"
if [[ -r "$VAULT_PLUGIN" ]]; then
   # shellcheck disable=SC1090
   source "$VAULT_PLUGIN"
fi

# Ensure _no_trace is defined
command -v _no_trace >/dev/null 2>&1 || _no_trace() { "$@"; }

JENKINS_CONFIG_DIR="$SCRIPT_DIR/etc/jenkins"

declare -a _JENKINS_RENDERED_MANIFESTS=()
_JENKINS_PREV_EXIT_TRAP_CMD=""
_JENKINS_PREV_EXIT_TRAP_HANDLER=""
_JENKINS_PREV_RETURN_TRAP_CMD=""
_JENKINS_PREV_RETURN_TRAP_HANDLER=""
JENKINS_MISSING_HOSTPATH_NODES=""
JENKINS_MOUNT_CHECK_ERROR=""

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
   quoted_handler=${quoted_handler% $signal}
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

function _jenkins_detect_cluster_name() {
   if [[ -n "${CLUSTER_NAME:-}" ]]; then
      printf '%s\n' "$CLUSTER_NAME"
      return 0
   fi

   local list_output
   if ! list_output=$(_k3d --no-exit --quiet cluster list); then
      echo "Failed to list k3d clusters. Set CLUSTER_NAME or create a cluster before deploying Jenkins." >&2
      return 1
   fi

   local -a clusters=()
   while IFS= read -r line; do
      line=${line%$'\r'}
      [[ -z "$line" ]] && continue
      [[ "$line" =~ ^[[:space:]]*NAME[[:space:]] ]] && continue
      read -r -a fields <<<"$line"
      if (( ${#fields[@]} )); then
         clusters+=("${fields[0]}")
      fi
   done <<<"$list_output"

   case ${#clusters[@]} in
      0)
         echo "No k3d clusters found. Create a cluster or export CLUSTER_NAME before deploying Jenkins." >&2
         return 1
         ;;
      1)
         printf '%s\n' "${clusters[0]}"
         return 0
         ;;
      *)
         echo "Multiple k3d clusters detected: ${clusters[*]}. Set CLUSTER_NAME to choose the target cluster before deploying Jenkins." >&2
         return 1
         ;;
   esac
}

function _jenkins_node_has_mount() {
   local node="$1"
   local host_path="$2"
   local cluster_path="$3"
   local inspect_output

   if ! inspect_output=$(_run_command --soft --quiet -- docker inspect "$node" --format '{{json .Mounts}}'); then
      return 2
   fi

   if [[ -z "$inspect_output" || "$inspect_output" == "null" ]]; then
      return 1
   fi

   if command -v jq >/dev/null 2>&1; then
      jq -e --arg src "$host_path" --arg dst "$cluster_path" \
         'map(select(.Source == $src and .Destination == $dst)) | length > 0' \
         <<<"$inspect_output" >/dev/null 2>&1
      local jq_rc=$?
      case $jq_rc in
         0) return 0 ;;
         1) return 1 ;;
         *) return 2 ;;
      esac
   fi

   if [[ "$inspect_output" == *"\"Source\":\"$host_path\""* && \
         "$inspect_output" == *"\"Destination\":\"$cluster_path\""* ]]; then
      return 0
   fi

   return 1
}

function _jenkins_require_hostpath_mounts() {
   local cluster="$1"
   local host_path="$JENKINS_HOME_PATH"
   local cluster_path="$JENKINS_HOME_IN_CLUSTER"
   local node_output

   JENKINS_MISSING_HOSTPATH_NODES=""
   JENKINS_MOUNT_CHECK_ERROR=""

   if ! node_output=$(_k3d --no-exit --quiet node list); then
      JENKINS_MOUNT_CHECK_ERROR="Failed to list k3d nodes for cluster $cluster. Ensure the cluster is running."
      return 1
   fi

   local -a workload_nodes=()
   while IFS= read -r line; do
      line=${line%$'\r'}
      [[ -z "$line" ]] && continue
      [[ "$line" =~ ^[[:space:]]*NAME[[:space:]] ]] && continue
      read -r -a fields <<<"$line"
      if (( ${#fields[@]} < 3 )); then
         continue
      fi
      local node_name="${fields[0]}"
      local node_role="${fields[1]}"
      local node_cluster="${fields[2]}"

      if [[ "$node_cluster" != "$cluster" ]]; then
         continue
      fi

      case "$node_role" in
         server|agent)
            workload_nodes+=("$node_name")
            ;;
      esac
   done <<<"$node_output"

   if (( ${#workload_nodes[@]} == 0 )); then
      JENKINS_MOUNT_CHECK_ERROR="No workload nodes found for k3d cluster $cluster."
      return 1
   fi

   local -a missing_nodes=()
   local node rc
   for node in "${workload_nodes[@]}"; do
      _jenkins_node_has_mount "$node" "$host_path" "$cluster_path"
      rc=$?
      case $rc in
         0)
            ;;
         1)
            missing_nodes+=("$node")
            ;;
         *)
            JENKINS_MOUNT_CHECK_ERROR="Failed to inspect k3d node $node for Jenkins hostPath mount."
            return 1
            ;;
      esac
   done

   if (( ${#missing_nodes[@]} )); then
      JENKINS_MISSING_HOSTPATH_NODES="${missing_nodes[*]}"
      return 1
   fi

   return 0
}

function _create_jenkins_pv_pvc() {
   local jenkins_namespace=$1

   export JENKINS_HOME_PATH="$SCRIPT_DIR/storage/jenkins_home"
   export JENKINS_HOME_IN_CLUSTER="/data/jenkins"
   export JENKINS_NAMESPACE="$jenkins_namespace"

   if _kubectl --no-exit get pv jenkins-home-pv >/dev/null 2>&1; then
      echo "Jenkins PV already exists, skip"
      return 0
   fi

   if [[ ! -d "$JENKINS_HOME_PATH" ]]; then
      echo "Creating Jenkins home directory at $JENKINS_HOME_PATH"
      mkdir -p "$JENKINS_HOME_PATH"
   fi

   local cluster_name
   if ! cluster_name=$(_jenkins_detect_cluster_name); then
      return 1
   fi

   if ! _jenkins_require_hostpath_mounts "$cluster_name"; then
      local missing_nodes="${JENKINS_MISSING_HOSTPATH_NODES:-}"
      local mount_error="${JENKINS_MOUNT_CHECK_ERROR:-}"

      if [[ -n "$mount_error" ]]; then
         echo "$mount_error" >&2
      else
         cat >&2 <<EOF
Jenkins requires the hostPath mount ${JENKINS_HOME_PATH}:${JENKINS_HOME_IN_CLUSTER} on all workload nodes, but these k3d nodes are missing it: ${missing_nodes}.
Update your cluster configuration so every node includes this mount, then recreate the cluster with './scripts/k3d-manager create_cluster ${cluster_name}' (set CLUSTER_PROVIDER if needed) before deploying Jenkins.
EOF
      fi
      return 1
   fi

   jenkins_pv_template="$(dirname "$SOURCE")/etc/jenkins/jenkins-home-pv.yaml.tmpl"
   if [[ ! -r "$jenkins_pv_template" ]]; then
      echo "Jenkins PV template file not found: $jenkins_pv_template"
      exit 1
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
   local pod="${vault_release}-0"

   if _kubectl --no-exit -n "$k8s_namespace" \
      get secret "$secret_name" >/dev/null 2>&1; then
      echo "TLS secret $secret_name already exists, skip"
      return 0
   fi

   if ! _kubectl --no-exit -n "$vault_namespace" exec -i "$pod" -- \
      sh -c 'vault secrets list | grep -q "^pki/"'; then
      _kubectl -n "$vault_namespace" exec -i "$pod" -- vault secrets enable pki
      _kubectl -n "$vault_namespace" exec -i "$pod" -- vault secrets tune -max-lease-ttl=87600h pki
      _kubectl -n "$vault_namespace" exec -i "$pod" -- \
         vault write pki/root/generate/internal common_name="dev.local.me" ttl=87600h
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

   _kubectl -n "$vault_namespace" exec -i "$pod" -- \
      vault write pki/roles/jenkins "${_jenkins_role_args[@]}"

   local json cert_file key_file
   json=$(_kubectl -n "$vault_namespace" exec -i "$pod" -- \
      vault write -format=json pki/issue/jenkins common_name="$common_name" ttl=72h)

   cert_file=$(mktemp -t jenkins-cert.XXXXXX.pem)
   key_file=$(mktemp -t jenkins-key.XXXXXX.pem)

   trap '$(_cleanup_trap_command "$cert_file" "$key_file")' RETURN
   trap '$(_cleanup_trap_command "$cert_file" "$key_file")' EXIT

   echo "$json" | jq -r '.data.certificate' > "$cert_file"
   echo "$json" | jq -r '.data.private_key' > "$key_file"

   _kubectl -n "$k8s_namespace" create secret tls "$secret_name" \
      --cert="$cert_file" --key="$key_file"

}

function _deploy_jenkins_image() {
   local ns="${1:-jenkins}"

   local jenkins_admin_sha="$(_bw_lookup_secret "jenkins-admin" "jenkins" | _sha256_12 )"
   local jenkins_admin_passwd_sha="$(_bw_lookup_secret "jenkins-admin-password" "jenkins" \
      | _sha256_12 )"
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

function _jenkins_running_on_wsl() {
   if declare -f _is_wsl >/dev/null 2>&1; then
      _is_wsl
      return $?
   fi

   return 1
}

function _jenkins_provider_is_k3s() {
   if declare -f cluster_provider_is >/dev/null 2>&1; then
      if cluster_provider_is k3s; then
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


function deploy_jenkins() {
   if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      echo "Usage: deploy_jenkins [namespace=jenkins] [vault-namespace=${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}] [vault-release=${VAULT_RELEASE_DEFAULT}]"
      return 0
   fi

   local jenkins_namespace="${1:-jenkins}"
   local vault_namespace="${2:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local vault_release="${3:-$VAULT_RELEASE_DEFAULT}"

   _jenkins_configure_leaf_host_defaults

   deploy_vault ha "$vault_namespace" "$vault_release"
   _create_jenkins_admin_vault_policy "$vault_namespace" "$vault_release"
   _create_jenkins_vault_ad_policy "$vault_namespace" "$vault_release" "$jenkins_namespace"
   _create_jenkins_cert_rotator_policy "$vault_namespace" "$vault_release" "" "" "$jenkins_namespace"
   _create_jenkins_namespace "$jenkins_namespace"
   _create_jenkins_pv_pvc "$jenkins_namespace"
   _ensure_jenkins_cert "$vault_namespace" "$vault_release"

   local deploy_rc
   _deploy_jenkins "$jenkins_namespace" "$vault_namespace" "$vault_release"
   deploy_rc=$?
   if (( deploy_rc != 0 )); then
      printf 'ERROR: Jenkins deployment failed; aborting readiness check.\n' >&2
      return "$deploy_rc"
   fi

   _wait_for_jenkins_ready "$jenkins_namespace"
}

function _deploy_jenkins() {
   local ns="${1:-jenkins}"
   local vault_namespace="${2:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local vault_release="${3:-$VAULT_RELEASE_DEFAULT}"

   local helm_repo_url_default="https://charts.jenkins.io"
   local helm_repo_url="${JENKINS_HELM_REPO_URL:-$helm_repo_url_default}"
   local helm_chart_ref_default="jenkins/jenkins"
   local helm_chart_ref="${JENKINS_HELM_CHART_REF:-$helm_chart_ref_default}"

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
   trap "$exit_trap_cmd" EXIT

   local return_trap_cmd="_jenkins_cleanup_rendered_manifests RETURN"
   if [[ -n "$_JENKINS_PREV_RETURN_TRAP_HANDLER" ]]; then
      return_trap_cmd+="; ${_JENKINS_PREV_RETURN_TRAP_HANDLER}"
   fi
   trap "$return_trap_cmd" RETURN

   if (( ! skip_repo_ops )); then
     if ! _helm repo list 2>/dev/null | grep -q jenkins; then
       _helm repo add jenkins "$helm_repo_url"
     fi
     _helm repo update
   fi
   _helm upgrade --install jenkins "$helm_chart_ref" \
      --namespace "$ns" \
      -f "$JENKINS_CONFIG_DIR/values.yaml"

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

   local vs_template="$JENKINS_CONFIG_DIR/virtualservice.yaml.tmpl"
   if [[ ! -r "$vs_template" ]]; then
      _err "VirtualService template file not found: $vs_template"
   fi

   local dr_template="$JENKINS_CONFIG_DIR/destinationrule.yaml.tmpl"
   if [[ ! -r "$dr_template" ]]; then
      _err "DestinationRule template file not found: $dr_template"
   fi

   export JENKINS_NAMESPACE="$ns"

   local vs_hosts_input="${JENKINS_VIRTUALSERVICE_HOSTS:-${VAULT_PKI_LEAF_HOST:-jenkins.dev.local.me}}"
   local -a vs_hosts_lines=()
   local -a _vs_hosts_split=()
   IFS=',' read -r -a _vs_hosts_split <<<"$vs_hosts_input"
   local _vs_host trimmed
   for _vs_host in "${_vs_hosts_split[@]}"; do
      trimmed="${_vs_host#${_vs_host%%[![:space:]]*}}"
      trimmed="${trimmed%${trimmed##*[![:space:]]}}"
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

   local jenkins_vars_file="$JENKINS_CONFIG_DIR/jenkins-vars.sh"
   if [[ -r "$jenkins_vars_file" ]]; then
      # shellcheck disable=SC1090
      source "$jenkins_vars_file"
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

   _vault_issue_pki_tls_secret "$vault_namespace" "$vault_release" "" "" \
      "$jenkins_host" "$secret_namespace" "$secret_name"

   local rc=$?
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
   local pod="${vault_release}-0"

   if _vault_policy_exists "$vault_namespace" "$vault_release" "jenkins-admin"; then
      _info "Vault policy jenkins-admin already exists, skip"
      return 0
   fi

   # create policy once (idempotent)
   cat <<'HCL' | tee jenkins-admin.hcl | _kubectl -n "$vault_namespace" exec -i "$pod" -- \
      vault write sys/policies/password/jenkins-admin policy=-
length = 24
rule "charset" { charset = "abcdefghijklmnopqrstuvwxyz" }
rule "charset" { charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ" }
rule "charset" { charset = "0123456789" }
rule "charset" { charset = "!@#$%^&*()-_=+[]{};:,.?" }
HCL

   cat <<'SCRIPT' | _no_trace _kubectl -n "$vault_namespace" exec -i "$pod" -- sh -
      set -euo pipefail
      jenkins_admin_pass=$(vault read -field=password sys/policies/password/jenkins-admin/generate)
      vault kv put secret/eso/jenkins-admin username=jenkins-admin password="$jenkins_admin_pass"
SCRIPT
   rm -f jenkins-admin.hcl
}

function _sync_vault_jenkins_admin() {
   local vault_namespace="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local vault_release="${2:-$VAULT_RELEASE_DEFAULT}"
   local jenkins_namespace="${3:-jenkins}"
   local pod="${vault_release}-0"
   _kubectl -n "$vault_namespace" exec -i "$pod" -- vault write -field=password \
      sys/policies/password/jenkins-admin/generate

   _kubectl -n "$vault_namespace" exec -i "$pod" -- sh - \
      vault kv put secret/eso/jenkins-admin \
      username=jenkins-admin password="$(_kubectl -n "$vault_namespace" exec -i "$pod" -- \
      vault read -field=password sys/policies/password/jenkins-admin/generate)"
}

function _create_jenkins_vault_ad_policy() {
   local vault_namespace="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local vault_release="${2:-$VAULT_RELEASE_DEFAULT}"
   local jenkins_namespace="${3:-jenkins}"
   local pod="${vault_release}-0"

   if ! _vault_policy_exists "$vault_namespace" "$vault_release" "jenkins-jcasc-read"; then
      _kubectl -n "$vault_namespace" exec -i "$pod" -- \
         vault policy write jenkins-jcasc-read - <<'HCL'
path "secret/data/jenkins/ad-ldap"     { capabilities = ["read"] }
path "secret/data/jenkins/ad-adreader" { capabilities = ["read"] }
HCL

      _kubectl -n "$vault_namespace" exec -i "$pod" -- \
         vault write auth/kubernetes/role/jenkins-jcasc-reader - \
           bound_service_account_names=jenkins \
           bound_service_account_namespaces="$jenkins_namespace" \
           policies=jenkins-jcasc-read \
           ttl=30m
   fi

   if ! _vault_policy_exists "$vault_namespace" "$vault_release" "jenkins-jcasc-write"; then
      _kubectl -n "$vault_namespace" exec -i "$pod" -- \
         vault policy write jenkins-jcasc-write - <<'HCL'
path "secret/data/jenkins/ad-ldap"     { capabilities = ["create", "update"] }
path "secret/data/jenkins/ad-adreader" { capabilities = ["create", "update"] }
HCL

      _kubectl -n "$vault_namespace" exec -i "$pod" -- \
         vault write auth/kubernetes/role/jenkins-jcasc-writer - \
           bound_service_account_names=jenkins \
           bound_service_account_namespaces="$jenkins_namespace" \
           policies=jenkins-jcasc-write \
           ttl=15m
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
   local pod="${vault_release}-0"

   local ensure_policy=1

   if _vault_policy_exists "$vault_namespace" "$vault_release" "$policy_name"; then
      local current_policy=""
      current_policy=$(_kubectl -n "$vault_namespace" exec -i "$pod" -- \
         vault policy read "$policy_name" 2>/dev/null || true)

      if [[ "$current_policy" == *"path \"${pki_path}/revoke\""* ]]; then
         ensure_policy=0
      fi
   fi

   if (( ensure_policy )); then
      cat <<HCL | _kubectl -n "$vault_namespace" exec -i "$pod" -- \
         vault policy write "$policy_name" -
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
   fi

   _kubectl -n "$vault_namespace" exec -i "$pod" -- \
      vault write auth/kubernetes/role/jenkins-cert-rotator \
        bound_service_account_names="$rotator_service_account" \
        bound_service_account_namespaces="$jenkins_namespace" \
        policies="$policy_name" \
        ttl=24h
}
