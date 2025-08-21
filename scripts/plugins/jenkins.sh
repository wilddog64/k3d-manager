if [[ ! -z "$DEBUG" ]]; then
   set -xv
fi

function _create_jenkins_namespace() {
   jenkins_namespace="${1:-jenkins}"
   export namespace="${jenkins_namespace}"
   jenkins_namespace_template="$(dirname $SOURCE)/etc/jenkins-namespace.yaml.tmpl"
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

   _kubectl create -n "$jenkins_namespace" \
      secret generic jenkins-admin \
      --from-literal=admin='admin' \
      --from-literal=admin-password=$(openssl rand -base64 16) 2>&1 > /dev/null
   echo "jenkins admin secret created"
}

function deploy_jenkins() {
   jenkins_namespace="${1:-jenkins}"

   _create_jenkins_namespace "$jenkins_namespace"
   _create_jenkins_secret "$jenkins_namespace" 
}
