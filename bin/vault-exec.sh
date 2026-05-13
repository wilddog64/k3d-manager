#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/system.sh
source "${REPO_ROOT}/scripts/lib/system.sh"
# shellcheck source=scripts/lib/identity_tools.sh
source "${REPO_ROOT}/scripts/lib/identity_tools.sh"

usage() {
  cat <<'EOF'
Usage: bin/vault-exec.sh [OPTIONS] [--] [COMMAND...]

Open a shell or run a command in the live Vault pod.

Options:
  -n, --namespace NS   Vault namespace (default: secrets)
  -p, --pod POD        Vault pod name (default: vault-0)
  -c, --container CTR  Vault container name (optional)
  -h, --help           Show this help

Examples:
  bin/vault-exec.sh
  bin/vault-exec.sh -- vault status
  bin/vault-exec.sh --namespace secrets -- vault kv list secret/
EOF
}

VAULT_NAMESPACE="${VAULT_NAMESPACE:-secrets}"
VAULT_POD="${VAULT_POD:-vault-0}"
VAULT_CONTAINER="${VAULT_CONTAINER:-}"
declare -a CMD=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace)
      VAULT_NAMESPACE="$2"
      shift 2
      ;;
    -p|--pod)
      VAULT_POD="$2"
      shift 2
      ;;
    -c|--container)
      VAULT_CONTAINER="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      CMD=("$@")
      break
      ;;
    *)
      CMD+=("$1")
      shift
      ;;
  esac
done

if [[ ${#CMD[@]} -eq 0 ]]; then
  CMD=(sh)
fi

_identity_exec_pod "$VAULT_NAMESPACE" "$VAULT_POD" "$VAULT_CONTAINER" "${CMD[@]}"
