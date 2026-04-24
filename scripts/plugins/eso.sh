#!/usr/bin/env bash
# scripts/plugins/external-secrets.sh
# External Secrets Operator plugin for k3d-manager

# shellcheck disable=SC1091

ESO_NAMESPACE="${ESO_NAMESPACE:-secrets}"
export ESO_NAMESPACE

function _eso_wait_for_webhook_endpoint() {
  local ns="${1:-${ESO_NAMESPACE:-secrets}}"
  local endpoint_ip=""
  local attempt

  _info "[eso] Waiting for external-secrets webhook endpoint..."
  for ((attempt=1; attempt<=18; attempt++)); do
    endpoint_ip=$(_kubectl --no-exit -n "$ns" get endpoints external-secrets-webhook \
      -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || true)
    if [[ -n "$endpoint_ip" ]]; then
      _info "[eso] external-secrets webhook ready (${endpoint_ip})"
      return 0
    fi
    sleep 10
  done

  _err "[eso] external-secrets webhook endpoint did not become ready"
  return 1
}

function _eso_wait_for_core_readiness() {
  local ns="${1:-${ESO_NAMESPACE:-secrets}}"
  local deployment
  local -a deployments=(
    external-secrets
    external-secrets-webhook
    external-secrets-cert-controller
  )

  for deployment in "${deployments[@]}"; do
    if ! _kubectl --no-exit -n "$ns" rollout status "deploy/${deployment}" --timeout=120s; then
      _err "[eso] deployment ${deployment} did not become ready"
      return 1
    fi
  done

  _eso_wait_for_webhook_endpoint "$ns"
}

function _eso_required_crds() {
  printf '%s\n' \
    secretstores.external-secrets.io \
    externalsecrets.external-secrets.io \
    clustersecretstores.external-secrets.io
}

function _eso_missing_crds() {
  local crd
  while IFS= read -r crd; do
    if ! _kubectl --no-exit get crd "$crd" >/dev/null 2>&1; then
      printf '%s\n' "$crd"
    fi
  done < <(_eso_required_crds)
}

function _eso_chart_skip_repo_ops() {
  local helm_chart_ref="$1"
  local helm_repo_url="$2"

  case "$helm_chart_ref" in
    /*|./*|../*|file://*) return 0 ;;
  esac
  case "$helm_repo_url" in
    ""|/*|./*|../*|file://*) return 0 ;;
  esac
  return 1
}

function _eso_install_chart() {
  local ns="$1"
  local helm_chart_ref="$2"
  local helm_repo_url="$3"

  if ! _eso_chart_skip_repo_ops "$helm_chart_ref" "$helm_repo_url"; then
    _helm repo add external-secrets "$helm_repo_url"
    _helm repo update >/dev/null 2>&1
  fi

  _helm upgrade --install -n "$ns" external-secrets "$helm_chart_ref" \
      --create-namespace \
      --set installCRDs=true
}

function _eso_wait_for_crds() {
  local crd
  local attempt

  while IFS= read -r crd; do
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
  done < <(_eso_required_crds)
}

# Install ESO (External Secrets Operator)
function deploy_eso() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: deploy_eso [namespace=${ESO_NAMESPACE:-secrets}] [release=external-secrets]"
    return 0
  fi
  local ns="${1:-${ESO_NAMESPACE:-secrets}}"
  local release="${2:-external-secrets}"

  local helm_repo_url_default="https://charts.external-secrets.io"
  local helm_repo_url="${ESO_HELM_REPO_URL:-$helm_repo_url_default}"
  local helm_chart_ref_default="external-secrets/external-secrets"
  local helm_chart_ref="${ESO_HELM_CHART_REF:-$helm_chart_ref_default}"

  local -a missing_crds=()
  local release_exists=0
  mapfile -t missing_crds < <(_eso_missing_crds)

  if _run_command --no-exit -- helm -n "$ns" status "$release" > /dev/null 2>&1 ; then
      release_exists=1
  fi

  if (( release_exists )) && (( ${#missing_crds[@]} == 0 )); then
      _eso_wait_for_core_readiness "$ns"
      echo "ESO already installed in namespace $ns"
      return 0
  fi

  if (( release_exists )) && (( ${#missing_crds[@]} > 0 )); then
      _warn "ESO release '$release' is present but required CRDs are missing; reapplying chart installation."
  fi

  # _kubectl --no-exit --quiet get ns "$ns" >/dev/null 2>&1 || _kubectl create ns "$ns"

  _eso_install_chart "$ns" "$helm_chart_ref" "$helm_repo_url"
  _eso_wait_for_crds

  _eso_wait_for_core_readiness "$ns"
  echo "ESO installed namespace $ns"

  if [[ -n "${REMOTE_VAULT_ADDR:-}" ]]; then
    _info "[eso] Configuring remote Vault SecretStore"
    _eso_configure_remote_vault "${ESO_REMOTE_SECRETSTORE_NAME:-remote-vault-store}" \
      "${ESO_REMOTE_SERVICE_ACCOUNT:-external-secrets}" \
      "${ESO_REMOTE_SERVICE_ACCOUNT_NAMESPACE:-${ns}}"
  fi
}

function _eso_configure_remote_vault() {
  local store_name="${1:-remote-vault-store}"
  local service_account="${2:-external-secrets}"
  local service_account_ns="${3:-${ESO_NAMESPACE:-secrets}}"
  local remote_addr="${REMOTE_VAULT_ADDR:-}"
  local mount_path="${REMOTE_VAULT_K8S_MOUNT:-kubernetes-app}"
  local vault_role="${REMOTE_VAULT_K8S_ROLE:-eso-app-cluster}"
  local vault_path="${REMOTE_VAULT_KV_PATH:-secret}"
  local store_kind="${ESO_REMOTE_SECRETSTORE_KIND:-ClusterSecretStore}"

  if [[ -z "$remote_addr" ]]; then
    _warn "[eso] REMOTE_VAULT_ADDR not set; skipping remote SecretStore configuration"
    return 0
  fi

  if [[ "$store_kind" == "SecretStore" ]]; then
    local target_namespace="${ESO_REMOTE_SECRETSTORE_NAMESPACE:-shopping-cart-data}"
    _kubectl create namespace "$target_namespace" --dry-run=client -o yaml | _kubectl apply -f - >/dev/null 2>&1 || true
    cat <<YAML | _kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: ${store_name}
  namespace: ${target_namespace}
spec:
  provider:
    vault:
      server: "${remote_addr}"
      path: "${vault_path}"
      version: v2
      auth:
        kubernetes:
          mountPath: "${mount_path}"
          role: "${vault_role}"
          serviceAccountRef:
            name: ${service_account}
            namespace: ${service_account_ns}
YAML
  else
    cat <<YAML | _kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: ${store_name}
spec:
  provider:
    vault:
      server: "${remote_addr}"
      path: "${vault_path}"
      version: v2
      auth:
        kubernetes:
          mountPath: "${mount_path}"
          role: "${vault_role}"
          serviceAccountRef:
            name: ${service_account}
            namespace: ${service_account_ns}
YAML
  fi
}
