VAULT_PLUGIN="$PLUGINS_DIR/vault.sh"
if [[ -r "$VAULT_PLUGIN" ]]; then
   # shellcheck disable=SC1090
   source "$VAULT_PLUGIN"
fi

# Ensure _no_trace is defined
command -v _no_trace >/dev/null 2>&1 || _no_trace() { "$@"; }

JENKINS_CONFIG_DIR="$SCRIPT_DIR/etc/jenkins"

function _create_jenkins_namespace() {
   jenkins_namespace="${1:-jenkins}"
   export namespace="${jenkins_namespace}"
   jenkins_namespace_template="$(dirname "$SOURCE")/etc/jenkins/jenkins-namespace.yaml.tmpl"
   if [[ ! -r "$jenkins_namespace_template" ]]; then
      echo "Jenkins namespace template file not found: $jenkins_namespace_template"
      exit 1
   fi
   yamlfile=$(mktemp -t)
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

function _create_jenkins_pv_pvc() {
   local jenkins_namespace=$1
   local cluster_name="${2:-$CLUSTER_NAME}"
   local detected_cluster_list
   local detected_cluster_name

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

   if [[ -z "$cluster_name" ]]; then
      if ! detected_cluster_list=$(_k3d cluster list 2>/dev/null); then
         echo "Unable to detect k3d cluster name; set CLUSTER_NAME or pass the cluster name explicitly." >&2
         return 1
      fi
      detected_cluster_name=$(awk 'NR>1 && NF {print $1; exit}' <<<"$detected_cluster_list")
      if [[ -z "$detected_cluster_name" ]]; then
         echo "Unable to detect k3d cluster name; set CLUSTER_NAME or pass the cluster name explicitly." >&2
         return 1
      fi
      cluster_name="$detected_cluster_name"
   fi

   jenkins_pv_template="$(dirname "$SOURCE")/etc/jenkins/jenkins-home-pv.yaml.tmpl"
   if [[ ! -r "$jenkins_pv_template" ]]; then
      echo "Jenkins PV template file not found: $jenkins_pv_template"
      exit 1
   fi
   jenkinsyamfile=$(mktemp -t)
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

   cert_file=$(mktemp -t jenkins-cert.pem.XXXX)
   key_file=$(mktemp -t jenkins-key.pem.XXXX)
   echo "$json" | jq -r '.data.certificate' > "$cert_file"
   echo "$json" | jq -r '.data.private_key' > "$key_file"

   _kubectl -n "$k8s_namespace" create secret tls "$secret_name" \
      --cert="$cert_file" --key="$key_file"

   rm -f "$cert_file" "$key_file"
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
   _deploy_jenkins "$jenkins_namespace"
   _wait_for_jenkins_ready "$jenkins_namespace"
}

function _deploy_jenkins() {
   local ns="${1:-jenkins}"

   if ! _helm repo list 2>/dev/null | grep -q jenkins; then
     _helm repo add jenkins https://charts.jenkins.io
   fi
   _helm repo update
   _helm upgrade --install jenkins jenkins/jenkins \
      --namespace "$ns" \
      -f "$JENKINS_CONFIG_DIR/values.yaml"

   # Ensure Istio resources are of the expected kind to avoid name collisions
   if ! grep -q '^kind: VirtualService' "$JENKINS_CONFIG_DIR/virtualservice.yaml"; then
      echo "virtualservice.yaml is not a VirtualService" >&2
      return 1
   fi

   if ! grep -q '^kind: DestinationRule' "$JENKINS_CONFIG_DIR/destinationrule.yaml"; then
      echo "destinationrule.yaml is not a DestinationRule" >&2
      return 1
   fi

   gw_yaml=$(_kubectl apply -n istio-system --dry-run=client \
      -f "$JENKINS_CONFIG_DIR/gateway.yaml")
   printf '%s\n' "$gw_yaml" | _kubectl apply -n istio-system -f -

   vs_yaml=$(_kubectl apply -n "$ns" --dry-run=client \
      -f "$JENKINS_CONFIG_DIR/virtualservice.yaml")
   printf '%s\n' "$vs_yaml" | _kubectl apply -n "$ns" -f -

   dr_yaml=$(_kubectl apply -n "$ns" --dry-run=client \
      -f "$JENKINS_CONFIG_DIR/destinationrule.yaml")
   printf '%s\n' "$dr_yaml" | _kubectl apply -n "$ns" -f -
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

   until _kubectl --no-exit -n "$ns" wait \
      pod -l app.kubernetes.io/component=jenkins-controller \
      --for=condition=Ready \
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

   local jenkins_admin_pass
   jenkins_admin_pass=$(_kubectl -n "$vault_namespace" exec -i "$pod" -- \
      vault read -field=password sys/policies/password/jenkins-admin/generate)
   printf '' | _no_trace _kubectl -n "$vault_namespace" exec -i "$pod" -- \
      vault kv put secret/eso/jenkins-admin username=jenkins-admin \
      password="$jenkins_admin_pass"
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
