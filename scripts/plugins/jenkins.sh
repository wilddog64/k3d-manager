VAULT_PLUGIN="$PLUGINS_DIR/vault.sh"
if [[ -r "$VAULT_PLUGIN" ]]; then
   # shellcheck disable=SC1090
   source "$VAULT_PLUGIN"
fi

JENKINS_CONFIG_DIR="$SCRIPT_DIR/etc/jenkins"
VALUT_PLUGIN="$PLUGINS_DIR/vault.sh"
if [[ -r "$VALUT_PLUGIN" ]]; then
   # shellcheck disable=SC1090
   source "$VALUT_PLUGIN"
fi

function _create_jenkins_namespace() {
   jenkins_namespace="${1:-jenkins}"
   export namespace="${jenkins_namespace}"
   jenkins_namespace_template="$(dirname "$SOURCE")/etc/jenkins/jenkins-namespace.yaml.tmpl"
   if [[ ! -r "$jenkins_namespace_template" ]]; then
      echo "Jenkins namespace template file not found: $jenkins_namespace_template"
      exit 1
   fi
   local yamfile=$(mktemp -t)
   envsubst < "$jenkins_namespace_template" > "$yamfile"

   if [[ $(_kubectl get namespace "$jenkins_namespace" 2>&1 > /dev/null) == 0 ]]; then
      echo "Namespace $jenkins_namespace already exists, skip"
   else
      _kubectl apply -f "$yamfile" > /dev/null 2>&1
      echo "Namespace $jenkins_namespace created"
   fi

   trap 'cleanup_on_success "$yamfile"' EXIT
}

function _create_jenkins_pv_pvc() {
   jenkins_namespace=$1

   export JENKINS_HOME_PATH="$SCRIPT_DIR/storage/jenkins_home"
   export JENINS_NAMESPACE="$jenkins_namespace"

   if _kubectl get pv | grep -q jenkins-home-pv >/dev/null 2>&1; then
      echo "Jenkins PV already exists, skip"
      return 0
   fi

   if [[ ! -d "$JENKINS_HOME_PATH" ]]; then
      echo "Creating Jenkins home directory at $JENKINS_HOME_PATH"
      mkdir -p "$JENKINS_HOME_PATH"
   fi

   jenkins_plugins="$SCRIPT_DIR/etc/jenkins/jenkins-plugins.txt"
   if [[ ! -r "$jenkins_plugins" ]]; then
      echo "Jenkins plugins file not found: $jenkins_plugins"
      exit 1
   else
      cp -v "${jenkins_plugins}" "$JENKINS_HOME_PATH"
   fi

   jenkins_pv_template="$(dirname $SOURCE)/etc/jenkins/jenkins-home-pv.yaml.tmpl"
   if [[ ! -r "$jenkins_pv_template" ]]; then
      echo "Jenkins PV template file not found: $jenkins_pv_template"
      exit 1
   fi
   jenkinsyamfile=$(mktemp -t)
   envsubst < "$jenkins_pv_template" > "$jenkinsyamfile"
   _kubectl apply -f "$jenkinsyamfile" -n "$jenkins_namespace"

   trap 'cleanup_on_success "$jenkinsyamfile"' EXIT
}

function _deploy_jenkins_image() {
   local ns="${1:-jenkins}"

   local jenkins_admin_sha="$(_bw_lookup_secret "jenkins-admin" "jenkins" | _sha256_12 )"
   local jenkins_admin_passwd_sha="$(_bw_lookup_secret "jenkins-admin-password" "jenkins" \
      | _sha256_12 )"

   if ! is_same_token "$jenkins_admin_sha" "$k3d_jenkins_admin_sha"; then
      _err "Jenkins admin user in k3d does NOT match Bitwarden!" >&2
   else
      _info "Jenkins admin user in k3d matches Bitwarden."
   fi
}

function deploy_jenkins() {
   jenkins_namespace="${1:-jenkins}"

   deploy_vault ha
   _create_jenkins_admin_vault_policy "vault"
   _create_jenkins_namespace "$jenkins_namespace"
   _deploy_jenkins "$jenkins_namespace"
}

function _deploy_jenkins() {
   local ns="${1:-jenkins}"

   _helm repo add jenkins https://charts.jenkins.io
   _helm repo update
   _helm upgrade --install jenkins jenkins/jenkins \
      --namespace "$ns" \
      -f "$JENKINS_CONFIG_DIR/values.yaml"

   cat "$JENKINS_CONFIG_DIR/virtualservice.yaml" | \
      _kubectl apply -n "$ns" --dry-run=client -f - | \
      _kubectl apply -n "$ns" -f -

   cat "$JENKINS_CONFIG_DIR/destinationrule.yaml" | \
      _kubectl apply -n "$ns" --dry-run=client -f - | \
      _kubectl apply -n "$ns" -f -
}

function _create_jenkins_admin_vault_policy() {
   local vault_namespace="${1:-vault}"

   if _vault_policy_exists "$vault_namespace" "jenkins-admin"; then
      _info "Vault policy jenkins-admin already exists, skip"
      return 0
   fi

   # create policy once (idempotent)
   cat > jenkins-admin.hcl <<'HCL' |
   _kubectl -n "$vault_namespace" exec -i vault-0 -- \
      vault write sys/policies/password/jenkins-admin policy=-
   length = 24
   rule "charset" { charset = "abcdefghijklmnopqrstuvwxyz" }
   rule "charset" { charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ" }
   rule "charset" { charset = "0123456789" }
   rule "charset" { charset = "!@#$%^&*()-_=+[]{};:,.?" }
HCL

   # generate + store under KV v2 path: secret/eso/jenkins-admin
   _kubectl -n "$vault_namespace" exec -i vault-0 -- vault write -field=password \
      sys/policies/password/jenkins-admin/generate

   _kubectl -n "$vault_namespace" exec -i vault-0 -- sh - \
      vault kv put secret/eso/jenkins-admin \
      username=admin password="$(_kubectl -n "$vault_namespace" exec -i vault-0 -- \
      vault read -field=password sys/policies/password/jenkins-admin/generate)"

}

function _sync_vault_jenkins_admin() {
   local vault_namespace="${1:-vault}"
   local jenkins_namespace="${2:-jenkins}"
   _kubectl -n "$vault_namespace" exec -i vault-0 -- vault write -field=password \
      sys/policies/password/jenkins-admin/generate

   _kubectl -n "$vault_namespace" exec -i vault-0 -- sh - \
      vault kv put secret/eso/jenkins-admin \
      username=admin password="$(_kubectl -n "$vault_namespace" exec -i vault-0 -- \
      vault read -field=password sys/policies/password/jenkins-admin/generate)"
}
