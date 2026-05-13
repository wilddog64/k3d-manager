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

usage() {
  cat <<'EOF'
Usage: bin/ldap-search.sh [OPTIONS] [ATTR...]

Search the live LDAP directory through the running LDAP pod.

Options:
  -n, --namespace NS     LDAP namespace (default: identity)
  -p, --pod POD          LDAP pod name (optional)
  -l, --label SELECTOR   Pod label selector (repeatable; default tries openldap labels)
  -b, --base-dn DN      LDAP base DN (default: dc=shopping-cart,dc=local)
  -f, --filter FILTER   LDAP filter (default: (objectClass=inetOrgPerson))
  -s, --secret NAME     Secret containing LDAP admin credentials (default: openldap-admin)
  -h, --help            Show this help

Examples:
  bin/ldap-search.sh --filter '(mail=admin@shopping-cart.local)' mail uid cn sn givenName
  bin/ldap-search.sh --base-dn 'ou=users,dc=shopping-cart,dc=local' --filter '(uid=admin)'
EOF
}

LDAP_NAMESPACE="${LDAP_NAMESPACE:-identity}"
LDAP_BASE_DN="${LDAP_BASE_DN:-dc=shopping-cart,dc=local}"
LDAP_SEARCH_FILTER="${LDAP_SEARCH_FILTER:-"(objectClass=inetOrgPerson)"}"
LDAP_ADMIN_SECRET_NAME="${LDAP_ADMIN_SECRET_NAME:-openldap-admin}"
LDAP_ADMIN_USERNAME_KEY="${LDAP_ADMIN_USERNAME_KEY:-LDAP_ADMIN_USERNAME}"
LDAP_ADMIN_PASSWORD_KEY="${LDAP_ADMIN_PASSWORD_KEY:-LDAP_ADMIN_PASSWORD}"
LDAP_PORT="${LDAP_PORT:-1389}"
LDAP_URL="${LDAP_URL:-ldap://127.0.0.1:${LDAP_PORT}}"
LDAP_BIND_DN="${LDAP_BIND_DN:-}"
LDAP_POD="${LDAP_POD:-}"
declare -a LDAP_LABELS=(
  "${LDAP_POD_LABEL:-app.kubernetes.io/name=openldap-bitnami}"
  "${LDAP_POD_LABEL_FALLBACK:-app.kubernetes.io/name=openldap}"
)
declare -a LDAP_ATTRS=()

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
    -l|--label)
      LDAP_LABELS+=("$2")
      shift 2
      ;;
    -b|--base-dn)
      LDAP_BASE_DN="$2"
      shift 2
      ;;
    -f|--filter)
      LDAP_SEARCH_FILTER="$2"
      shift 2
      ;;
    -s|--secret)
      LDAP_ADMIN_SECRET_NAME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      LDAP_ATTRS=("$@")
      break
      ;;
    *)
      LDAP_ATTRS+=("$1")
      shift
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

if [[ -z "$LDAP_BIND_DN" ]]; then
  LDAP_BIND_DN="$(_identity_secret_field "$LDAP_NAMESPACE" "$LDAP_ADMIN_SECRET_NAME" "$LDAP_ADMIN_USERNAME_KEY" || true)"
  if [[ -n "$LDAP_BIND_DN" && "$LDAP_BIND_DN" != *"="* ]]; then
    LDAP_BIND_DN="cn=${LDAP_BIND_DN},${LDAP_BASE_DN}"
  fi
  if [[ -z "$LDAP_BIND_DN" ]]; then
    LDAP_BIND_DN="cn=admin,${LDAP_BASE_DN}"
  fi
fi

LDAP_BIND_PASSWORD="$(_identity_secret_field "$LDAP_NAMESPACE" "$LDAP_ADMIN_SECRET_NAME" "$LDAP_ADMIN_PASSWORD_KEY" || true)"
if [[ -z "$LDAP_BIND_PASSWORD" ]]; then
  _err "Could not read LDAP admin password from secret '$LDAP_ADMIN_SECRET_NAME' in namespace '$LDAP_NAMESPACE'"
  exit 1
fi

ldap_script=$(cat <<'SH'
ldap_url="$1"
bind_dn="$2"
base_dn="$3"
filter="$4"
shift 4
tmp_pw="$(mktemp)"
trap 'rm -f "$tmp_pw"' EXIT
cat >"$tmp_pw"
exec ldapsearch -x -H "$ldap_url" -D "$bind_dn" -y "$tmp_pw" -b "$base_dn" "$filter" "$@"
SH
)

printf '%s\n' "$LDAP_BIND_PASSWORD" | _run_command --quiet -- kubectl exec -i -n "$LDAP_NAMESPACE" "$LDAP_POD" -- sh -c "$ldap_script" -- \
  "$LDAP_URL" "$LDAP_BIND_DN" "$LDAP_BASE_DN" "$LDAP_SEARCH_FILTER" "${LDAP_ATTRS[@]}"
