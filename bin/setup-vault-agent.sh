#!/usr/bin/env bash
set -euo pipefail

VAULT_NAMESPACE=${VAULT_NAMESPACE:-${VAULT_NS:-vault}}
VAULT_RELEASE=${VAULT_RELEASE:-vault}
HELM_BIN=${HELM_BIN:-helm}
KUBECTL_BIN=${KUBECTL_BIN:-kubectl}
JENKINS_NAMESPACE=${JENKINS_NAMESPACE:-jenkins}
JENKINS_SERVICE_ACCOUNT=${JENKINS_SERVICE_ACCOUNT:-jenkins}
VAULT_ROLE_NAME=${VAULT_ROLE_NAME:-jenkins-jcasc-reader}
VAULT_POLICY_NAME=${VAULT_POLICY_NAME:-jenkins-jcasc-read}
VAULT_SECRET_PATH=${VAULT_SECRET_PATH:-secret/data/jenkins/ad-ldap}

usage() {
  cat <<'USAGE'
Usage: setup-vault-agent.sh [--vault-namespace ns] [--vault-release name]
                            [--jenkins-namespace ns] [--jenkins-service-account sa]

Ensures the HashiCorp Vault Agent Injector is enabled on the Vault Helm release
and creates a Kubernetes auth role that lets Jenkins read the AD bind secret.
Environment variables: VAULT_NAMESPACE, VAULT_RELEASE, JENKINS_NAMESPACE,
JENKINS_SERVICE_ACCOUNT, VAULT_ROLE_NAME, VAULT_POLICY_NAME, VAULT_SECRET_PATH.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault-namespace) VAULT_NAMESPACE="$2"; shift 2 ;;
    --vault-release) VAULT_RELEASE="$2"; shift 2 ;;
    --jenkins-namespace) JENKINS_NAMESPACE="$2"; shift 2 ;;
    --jenkins-service-account) JENKINS_SERVICE_ACCOUNT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

command -v "$HELM_BIN" >/dev/null || { echo "helm not found" >&2; exit 1; }
command -v "$KUBECTL_BIN" >/dev/null || { echo "kubectl not found" >&2; exit 1; }

if ! "$HELM_BIN" status "$VAULT_RELEASE" -n "$VAULT_NAMESPACE" >/dev/null 2>&1; then
  echo "Vault release '$VAULT_RELEASE' not found in namespace '$VAULT_NAMESPACE'." >&2
  echo "Deploy Vault first, then rerun this script." >&2
  exit 1
fi

CHART_VERSION="${VAULT_CHART_VERSION:-}"
if [[ -z "$CHART_VERSION" ]]; then
  CHART_LINE=$("$HELM_BIN" history "$VAULT_RELEASE" -n "$VAULT_NAMESPACE" --max=1 | awk 'NR==2 {print $3}')
  if [[ "$CHART_LINE" == vault-* ]]; then
    CHART_VERSION="${CHART_LINE#vault-}"
  fi
fi

TMP_VALUES=$(mktemp -t vault-injector-values.XXXXXX.yaml)
trap 'rm -f "$TMP_VALUES"' EXIT

cat >"$TMP_VALUES" <<'VALUES'
injector:
  enabled: true
  metrics:
    enabled: false
VALUES

HELM_ARGS=(upgrade "$VAULT_RELEASE" hashicorp/vault -n "$VAULT_NAMESPACE" -f "$TMP_VALUES" --reuse-values --wait)
if [[ -n "$CHART_VERSION" ]]; then
  HELM_ARGS+=(--version "$CHART_VERSION")
fi

"$HELM_BIN" "${HELM_ARGS[@]}"

if ! "$KUBECTL_BIN" -n "$VAULT_NAMESPACE" rollout status deployment/vault-agent-injector --timeout=180s; then
  echo "Vault Agent Injector failed to reach Ready state." >&2
  exit 1
fi

ROOT_TOKEN_B64=$("$KUBECTL_BIN" -n "$VAULT_NAMESPACE" get secret vault-root -o jsonpath='{.data.root_token}' 2>/dev/null || true)
if [[ -z "$ROOT_TOKEN_B64" ]]; then
  echo "vault-root secret not found in namespace '$VAULT_NAMESPACE'." >&2
  exit 1
fi
ROOT_TOKEN=$(printf '%s' "$ROOT_TOKEN_B64" | base64 -d)
if [[ -z "$ROOT_TOKEN" ]]; then
  echo "Vault root token is empty." >&2
  exit 1
fi

VAULT_POD="${VAULT_RELEASE}-0"

"$KUBECTL_BIN" -n "$VAULT_NAMESPACE" exec -i "$VAULT_POD" -- env VAULT_TOKEN="$ROOT_TOKEN" \
  vault policy write "$VAULT_POLICY_NAME" - <<POLICY
path "$VAULT_SECRET_PATH" { capabilities = ["read"] }
POLICY

"$KUBECTL_BIN" -n "$VAULT_NAMESPACE" exec -i "$VAULT_POD" -- env VAULT_TOKEN="$ROOT_TOKEN" \
  vault write auth/kubernetes/role/"$VAULT_ROLE_NAME" \
    bound_service_account_names="$JENKINS_SERVICE_ACCOUNT" \
    bound_service_account_namespaces="$JENKINS_NAMESPACE" \
    policies="$VAULT_POLICY_NAME" \
    ttl="30m"

echo "Vault Agent Injector enabled and role '$VAULT_ROLE_NAME' mapped to service account '$JENKINS_SERVICE_ACCOUNT' in namespace '$JENKINS_NAMESPACE'."
