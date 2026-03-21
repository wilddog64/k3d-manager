#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

_info() { printf 'INFO: %s
' "$*"; }
_warn() { printf 'WARN: %s
' "$*" >&2; }
_err() { printf 'ERROR: %s
' "$*" >&2; }

: "${KUBECTL:=kubectl}"
VAULT_HEALTH_NS="${VAULT_NS:-secrets}"
VAULT_HEALTH_RELEASE="${VAULT_RELEASE:-vault}"

check_rollout() {
  local resource="$1" namespace="$2" timeout="${3:-120s}"
  _info "Waiting for $resource in namespace $namespace..."
  if ! $KUBECTL -n "$namespace" wait "$resource" \
      --for=condition=Available --timeout="$timeout"; then
    _err "$resource in namespace $namespace is not Ready"
    return 1
  fi
}

check_statefulset_ready() {
  local name="$1" namespace="$2"
  _info "Checking StatefulSet $name in namespace $namespace..."
  local desired ready
  desired=$($KUBECTL -n "$namespace" get statefulset "$name" -o jsonpath='{.status.replicas}' || echo "")
  ready=$($KUBECTL -n "$namespace" get statefulset "$name" -o jsonpath='{.status.readyReplicas}' || echo "")
  if [[ -z "$desired" ]]; then
    _err "StatefulSet $name not found in $namespace"
    return 1
  fi
  ready="${ready:-0}"
  if [[ "$desired" != "$ready" ]]; then
    _err "StatefulSet $name Ready replicas $ready does not match desired $desired"
    return 1
  fi
}

check_pods_ready() {
  local namespace="$1"
  _info "Checking pods in namespace $namespace..."
  if ! $KUBECTL -n "$namespace" get pods >/dev/null 2>&1; then
    _warn "Namespace $namespace has no pods"
    return 0
  fi
  if ! $KUBECTL -n "$namespace" wait --for=condition=Ready pods --all --timeout=120s; then
    _err "Pods in namespace $namespace failed to reach Ready state"
    return 1
  fi
}

check_vault_status() {
  local namespace="${1:-$VAULT_HEALTH_NS}" pod="${2:-${VAULT_HEALTH_RELEASE}-0}"
  _info "Checking Vault status via $namespace/$pod..."
  local status
  if ! status=$($KUBECTL -n "$namespace" exec -i "$pod" -- vault status 2>&1); then
    printf '%s
' "$status" >&2
    _err "Failed to execute vault status"
    return 1
  fi
  if ! grep -q 'Initialized *true' <<<"$status"; then
    printf '%s
' "$status" >&2
    _err "Vault is not initialized"
    return 1
  fi
  if ! grep -q 'Sealed *false' <<<"$status"; then
    printf '%s
' "$status" >&2
    _err "Vault is sealed"
    return 1
  fi
}

main() {
  check_rollout deployment/istio-ingressgateway istio-system "300s"
  check_statefulset_ready vault "$VAULT_HEALTH_NS"
  check_pods_ready "$VAULT_HEALTH_NS"
  check_vault_status "$VAULT_HEALTH_NS" "${VAULT_HEALTH_RELEASE}-0"
  _info "Cluster health check passed"
}

main "$@"
