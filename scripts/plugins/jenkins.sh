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
         handler_literal=${quoted_handler:1:-1}
         handler_literal=${handler_literal//\'\\\'\'/\'}
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
   yamlfile=$(mktemp -t)
   trap '_cleanup_on_success "$yamlfile"' EXIT
   # shellcheck disable=SC
   envsubst < "$jenkins_namespace_template" > "$yamlfile"

   if _kubectl --no-exit get namespace "$jenkins_namespace" >/dev/null 2>&1; then
      echo "Namespace $jenkins_namespace already exists, skip"
   else
      _kubectl apply -f "$yamlfile" >/dev/null 2>&1
      echo "Namespace $jenkins_namespace created"
   fi

   trap '_cleanup_on_success "$yamlfile"' RETURN
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

   if ! node_output=$(_k3d --no-exit --quiet node list --cluster "$cluster"); then
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
Recreate the cluster with './scripts/k3d-manager create_k3d_cluster ${cluster_name}' or patch the nodes (for example: 'k3d node edit <node> --volume-add ${JENKINS_HOME_PATH}:${JENKINS_HOME_IN_CLUSTER}') before deploying Jenkins.
EOF
      fi
      return 1
   fi

   jenkins_pv_template="$(dirname "$SOURCE")/etc/jenkins/jenkins-home-pv.yaml.tmpl"
   if [[ ! -r "$jenkins_pv_template" ]]; then
      echo "Jenkins PV template file not found: $jenkins_pv_template"
      exit 1
   fi
   jenkinsyamfile=$(mktemp -t)
   trap '_cleanup_on_success "$jenkinsyamfile"' EXIT
   envsubst < "$jenkins_pv_template" > "$jenkinsyamfile"
   _kubectl apply -f "$jenkinsyamfile" -n "$jenkins_namespace"

   trap '_cleanup_on_success "$jenkinsyamfile"' EXIT
}

function _ensure_jenkins_cert() {
   local vault_namespace="${1:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local vault_release="${2:-$VAULT_RELEASE_DEFAULT}"
   local k8s_namespace="istio-system"
   local secret_name="jenkins-cert"
   local common_name="jenkins.dev.local.me"
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

   _kubectl -n "$vault_namespace" exec -i "$pod" -- \
      vault write pki/roles/jenkins allowed_domains=dev.local.me allow_subdomains=true max_ttl=72h

   local json cert_file key_file
   json=$(_kubectl -n "$vault_namespace" exec -i "$pod" -- \
      vault write -format=json pki/issue/jenkins common_name="$common_name" ttl=72h)

   cert_file=$(mktemp -t)
   key_file=$(mktemp -t)
   declare -a CLEANUP_FILES=("$cert_file" "$key_file")
   local cleanup_cmd
   printf -v cleanup_cmd '_cleanup_on_success %q %q' "$cert_file" "$key_file"
   trap "$cleanup_cmd" EXIT

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

function deploy_jenkins() {
   if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      echo "Usage: deploy_jenkins [namespace=jenkins] [vault-namespace=${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}] [vault-release=${VAULT_RELEASE_DEFAULT}]"
      return 0
   fi

   local jenkins_namespace="${1:-jenkins}"
   local vault_namespace="${2:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local vault_release="${3:-$VAULT_RELEASE_DEFAULT}"

   deploy_vault ha "$vault_namespace" "$vault_release"
   _create_jenkins_admin_vault_policy "$vault_namespace" "$vault_release"
   _create_jenkins_vault_ad_policy "$vault_namespace" "$vault_release" "$jenkins_namespace"
   _create_jenkins_namespace "$jenkins_namespace"
   _create_jenkins_pv_pvc "$jenkins_namespace"
   _ensure_jenkins_cert "$vault_namespace" "$vault_release"
   _deploy_jenkins "$jenkins_namespace" "$vault_namespace" "$vault_release"
   _wait_for_jenkins_ready "$jenkins_namespace"
}

function _deploy_jenkins() {
   local ns="${1:-jenkins}"
   local vault_namespace="${2:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local vault_release="${3:-$VAULT_RELEASE_DEFAULT}"

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

   if ! _helm repo list 2>/dev/null | grep -q jenkins; then
     _helm repo add jenkins https://charts.jenkins.io
   fi
   _helm repo update
   _helm upgrade --install jenkins jenkins/jenkins \
      --namespace "$ns" \
      -f "$JENKINS_CONFIG_DIR/values.yaml"

   local gw_yaml="$JENKINS_CONFIG_DIR/gateway.yaml"
   if [[ ! -r "$gw_yaml" ]]; then
      _err "Gateway YAML file not found: $gw_yaml"
   fi
   if ! _kubectl apply -n istio-system --dry-run=client -f "$gw_yaml"; then
      local rc=$?
      _jenkins_cleanup_and_return "$rc"
      return $?
   fi
   if ! _kubectl apply -n istio-system -f - < "$gw_yaml"; then
      local rc=$?
      _jenkins_cleanup_and_return "$rc"
      return $?
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

   local vs_rendered
   vs_rendered=$(mktemp -t jenkins-virtualservice.XXXXXX.yaml)
   _jenkins_register_rendered_manifest "$vs_rendered"
   envsubst < "$vs_template" > "$vs_rendered"

   local dr_rendered
   dr_rendered=$(mktemp -t jenkins-destinationrule.XXXXXX.yaml)
   _jenkins_register_rendered_manifest "$dr_rendered"
   envsubst < "$dr_template" > "$dr_rendered"

   if ! _kubectl apply -n "$ns" --dry-run=client -f "$vs_rendered"; then
      local rc=$?
      _jenkins_cleanup_and_return "$rc"
      return $?
   fi
   if ! _kubectl apply -n "$ns" -f "$vs_rendered"; then
      local rc=$?
      _jenkins_cleanup_and_return "$rc"
      return $?
   fi

   if ! _kubectl apply -n "$ns" --dry-run=client -f "$dr_rendered"; then
      local rc=$?
      _jenkins_cleanup_and_return "$rc"
      return $?
   fi
   if ! _kubectl apply -n "$ns" -f "$dr_rendered"; then
      local rc=$?
      _jenkins_cleanup_and_return "$rc"
      return $?
   fi

   local jenkins_host="jenkins.dev.local.me"
   local secret_namespace="istio-system"
   local secret_name="jenkins-cert"

   _vault_issue_pki_tls_secret "$vault_namespace" "$vault_release" "" "" \
      "$jenkins_host" "$secret_namespace" "$secret_name"

   local rc=$?
   _jenkins_cleanup_and_return "$rc"
   return $?
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
