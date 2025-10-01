export IP=$(ip -4 route get 8.8.8.8 | perl -nle 'print $1 if /src (.*) uid/')

# Default ports for cluster load balancer
export HTTP_PORT="${HTTP_PORT:-8089}"
export HTTPS_PORT="${HTTPS_PORT:-8443}"
export JENKINS_HOME_PATH="${JENKINS_HOME_PATH:-${SCRIPT_DIR}/storage/jenkins_home}"
export JENKINS_HOME_IN_CLUSTER="${JENKINS_HOME_IN_CLUSTER:-/data/jenkins}"
