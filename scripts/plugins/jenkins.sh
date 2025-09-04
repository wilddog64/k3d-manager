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
   jenkins_version="${2:-lts}"

   _create_jenkins_namespace "$jenkins_namespace"
   _create_jenkins_pv_pvc "$jenkins_namespace"
}
