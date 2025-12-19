# scripts/plugins/external-secrets.sh
# External Secrets Operator plugin for k3d-manager

# Install ESO (External Secrets Operator)
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

  local -a required_crds=(
    secretstores.external-secrets.io
    externalsecrets.external-secrets.io
    clustersecretstores.external-secrets.io
  )

  local -a missing_crds=()
  local crd
  for crd in "${required_crds[@]}"; do
    if ! _kubectl --no-exit get crd "$crd" >/dev/null 2>&1; then
      missing_crds+=("$crd")
    fi
  done

  local release_exists=0
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
      release_exists=1
  fi

  if (( release_exists )) && (( ${#missing_crds[@]} == 0 )); then
      echo "ESO already installed in namespace $ns"
      return 0
  fi

  if (( release_exists )) && (( ${#missing_crds[@]} > 0 )); then
      _warn "ESO release '$release' is present but required CRDs are missing; reapplying chart installation."
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

  for crd in "${required_crds[@]}"; do
    local observed=0
    for ((attempt=0; attempt<12; attempt++)); do
      if _kubectl --no-exit get crd "$crd" >/dev/null 2>&1; then
        observed=1
        break
      fi
      sleep 5
    done
    if (( ! observed )); then
      _warn "CRD ${crd} not detected after 60 seconds; verify the ESO installation if issues persist."
      continue
    fi
    if ! _kubectl --no-exit wait --for=condition=Established --timeout=120s "crd/${crd}" >/dev/null 2>&1; then
      _warn "Timed out waiting for CRD ${crd} to become ready; verify the ESO installation if issues persist."
    fi
  done

  # Wait for controllers and the SDK server
  _kubectl -n "$ns" rollout status deploy/external-secrets --timeout=120s
  echo "ESO installed namespace $ns"
}
