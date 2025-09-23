# scripts/plugins/external-secrets.sh
# External Secrets Operator + Bitwarden Secrets Manager plugin for k3d-manager

# Install ESO and enable the Bitwarden SDK server dependency
function deploy_eso() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: deploy_eso [namespace=external-secrets] [release=external-secrets]"
    return 0
  fi
  local ns="${1:-external-secrets}"
  local release="${2:-external-secrets}"

  local helm_repo_url_default="https://charts.external-secrets.io"
  local helm_repo_url="${ESO_HELM_REPO_URL:-$helm_repo_url_default}"
  local helm_chart_ref_default="external-secrets/external-secrets"
  local helm_chart_ref="${ESO_HELM_CHART_REF:-$helm_chart_ref_default}"

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

  if _run_command --no-exit -- helm -n "$ns" status "$release" > /dev/null 2>&1 ; then
      echo "ESO already installed in namespace $ns"
      return 0
  fi

  # _kubectl --no-exit --quiet get ns "$ns" >/dev/null 2>&1 || _kubectl create ns "$ns"

  # Helm repo
  if (( ! skip_repo_ops )); then
    _helm repo add external-secrets "$helm_repo_url"
    _helm repo update >/dev/null 2>&1
  fi
  _helm upgrade --install -n "$ns" external-secrets "$helm_chart_ref" \
      --create-namespace \
      --set installCRDs=true

  # Wait for controllers and the SDK server
  _kubectl -n "$ns" rollout status deploy/external-secrets --timeout=120s
  echo "ESO installed namespace $ns"
}

