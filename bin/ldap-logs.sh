#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2317

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/system.sh
source "${REPO_ROOT}/scripts/lib/system.sh"
# shellcheck source=scripts/lib/identity_tools.sh
source "${REPO_ROOT}/scripts/lib/identity_tools.sh"

LDAP_NAMESPACE="${LDAP_NAMESPACE:-identity}"
LDAP_POD="${LDAP_POD:-}"
LDAP_TAIL="${LDAP_TAIL:-200}"
declare -a LDAP_LABELS=(
  "${LDAP_POD_LABEL:-app.kubernetes.io/name=openldap-bitnami}"
  "${LDAP_POD_LABEL_FALLBACK:-app.kubernetes.io/name=openldap}"
)

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace)
      LDAP_NAMESPACE="$2"
      shift 2
      ;;
    -p|--pod)
      LDAP_POD="$2"
      shift 2
      ;;
    -t|--tail)
      LDAP_TAIL="$2"
      shift 2
      ;;
    -l|--label)
      LDAP_LABELS+=("$2")
      shift 2
      ;;
    -f|--follow)
      LDAP_FOLLOW=1
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: bin/ldap-logs.sh [OPTIONS]
  -n, --namespace NS   LDAP namespace (default: identity)
  -p, --pod POD        LDAP pod name (optional)
  -t, --tail N         Number of log lines to show (default: 200)
  -l, --label SEL      Pod label selector (repeatable)
  -f, --follow         Follow logs
EOF
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

if [[ -z "$LDAP_POD" ]]; then
  LDAP_POD="$(_identity_first_pod "$LDAP_NAMESPACE" "${LDAP_LABELS[@]}")"
fi
if [[ -z "$LDAP_POD" ]]; then
  _err "Could not find an LDAP pod in namespace '$LDAP_NAMESPACE'"
  exit 1
fi

declare -a LOG_ARGS=(--tail="$LDAP_TAIL")
if [[ "${LDAP_FOLLOW:-0}" == "1" ]]; then
  LOG_ARGS+=(-f)
fi

_identity_logs_pod "$LDAP_NAMESPACE" "$LDAP_POD" "${LOG_ARGS[@]}"
