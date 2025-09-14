export IP=$(ip -4 route get 8.8.8.8 | perl -nle 'print $1 if /src (.*) uid/')

# Default ports for cluster load balancer
export HTTP_PORT="${HTTP_PORT:-8080}"
export HTTPS_PORT="${HTTPS_PORT:-8443}"
