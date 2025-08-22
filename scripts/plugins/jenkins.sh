if [[ ! -z "$DEBUG" ]]; then
   set -xv
fi

function _create_jenkins_namespace() {
   jenkins_namespace="${1:-jenkins}"
   export namespace="${jenkins_namespace}"
   jenkins_namespace_template="$(dirname $SOURCE)/etc/jenkins/jenkins-namespace.yaml.tmpl"
   if [[ ! -r "$jenkins_namespace_template" ]]; then
      echo "Jenkins namespace template file not found: $jenkins_namespace_template"
      exit 1
   fi
   local yamfile=$(mktemp -t)
   envsubst < "$jenkins_namespace_template" > "$yamfile"
   if _kubectl get namespace "$jenkins_namespace" >/dev/null 2>&1; then
      echo "Namespace $jenkins_namespace already exists, skip"
   else
      _kubectl apply -f "$yamfile"
      echo "Namespace $jenkins_namespace created"
   fi

   trap 'cleanup_on_success "$yamfile"' EXIT
}

function _create_jenkins_secret() {
   jenkins_namespce=$1

   if _kubectl get secret jenkins-admin -n "$jenkins_namespace" >/dev/null 2>&1; then
      echo "jenkins admin secret already exists, skip"
      return 0
   fi

   _kubectl create -n "$jenkins_namespace" \
      secret generic jenkins-admin \
      --from-literal=admin='admin' \
      --from-literal=admin-password=$(openssl rand -base64 16) 2>&1 > /dev/null
   echo "jenkins admin secret created"
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
   jenkins_namespace=$2
   jenkins_version=$1
}

function deploy_jenkins() {
   jenkins_namespace="${1:-jenkins}"
   jenkins_version="${2:-lts}"

   _create_jenkins_namespace "$jenkins_namespace"
   _create_jenkins_secret "$jenkins_namespace"
   _create_jenkins_pv_pvc "$jenkins_namespace"
}
