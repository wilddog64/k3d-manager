# scripts/plugins/external-secrets.sh
# External Secrets Operator + Bitwarden Secrets Manager plugin for k3d-manager

# Install ESO and enable the Bitwarden SDK server dependency
function deploy_eso() {
  local ns="${1:-external-secrets}"
  local release="${2:-external-secrets}"

  if _run_command --no-exit -- helm -n "$ns" status "$release" > /dev/null 2>&1 ; then
      echo "ESO already installed in namespace $ns"
      return 0
  fi

  # _kubectl --no-exit --quiet get ns "$ns" >/dev/null 2>&1 || _kubectl create ns "$ns"

  # Helm repo
  _helm repo add external-secrets https://charts.external-secrets.io
  _helm repo update >/dev/null 2>&1
  _helm upgrade --install -n "$ns" external-secrets external-secrets/external-secrets \
      --create-namespace \
      --set installCRDs=true

  # Wait for controllers and the SDK server
  _kubectl -n "$ns" rollout status deploy/external-secrets --timeout=120s
  echo "ESO installed namespace $ns"
}

