#!/usr/bin/env bash
set -euo pipefail

namespace="${1:-directory}"
release="${2:-openldap}"
service="${3:-${release}-openldap-bitnami}"
local_port="${4:-3389}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required for this smoke test" >&2
  exit 1
fi

if ! command -v ldapsearch >/dev/null 2>&1; then
  cat <<'EOF' >&2
ldapsearch is required for this smoke test.
Install the ldap-utils package (e.g. apt-get install ldap-utils or brew install openldap).
EOF
  exit 1
fi

echo "Fetching admin credentials from ${namespace}/openldap-admin"
LDAP_USER=$(kubectl -n "$namespace" get secret openldap-admin -o jsonpath='{.data.LDAP_ADMIN_USERNAME}' | base64 -d | tr -d '\n')
LDAP_PASS=$(kubectl -n "$namespace" get secret openldap-admin -o jsonpath='{.data.LDAP_ADMIN_PASSWORD}' | base64 -d | tr -d '\n')
BASE_DN_INPUT="${5:-}"

echo "Port-forwarding ${namespace}/${service} to localhost:${local_port}"
kubectl -n "$namespace" port-forward "svc/$service" "${local_port}:389" >/tmp/ldap-portforward.log 2>&1 &
PF_PID=$!
sleep 3

if ! kill -0 "$PF_PID" >/dev/null 2>&1; then
  echo "Port-forward failed:" >&2
  cat /tmp/ldap-portforward.log >&2
  exit 1
fi

cleanup() {
  kill "$PF_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

BASE_DN="$BASE_DN_INPUT"

if [[ -z "$BASE_DN" ]]; then
  BASE_DN=$(kubectl -n "$namespace" get secret openldap-admin -o jsonpath='{.data.LDAP_BASE_DN}' 2>/dev/null | base64 -d | tr -d '\n' || true)
fi

if [[ -z "$BASE_DN" ]]; then
  pod_name=$(kubectl -n "$namespace" get pods -l app.kubernetes.io/instance="$release" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -n "$pod_name" ]]; then
    BASE_DN=$(kubectl -n "$namespace" exec "$pod_name" -c openldap-bitnami -- printenv LDAP_ROOT 2>/dev/null | tr -d '\r\n' || true)
    if [[ -z "$BASE_DN" ]]; then
      BASE_DN=$(kubectl -n "$namespace" exec "$pod_name" -c openldap-bitnami -- printenv LDAP_BASE_DN 2>/dev/null | tr -d '\r\n' || true)
    fi
  fi
fi

if [[ -z "$BASE_DN" ]]; then
  BASE_DN=$(LDAPTLS_REQCERT=never ldapsearch -x \
    -H "ldap://127.0.0.1:$local_port" \
    -s base -b "" namingContexts 2>/dev/null | awk '/^namingContexts:/{print $2; exit}' || true)
fi

BASE_DN=${BASE_DN:-"dc=home,dc=org"}

BIND_DN="$LDAP_USER"
if [[ "$BIND_DN" != *"="* ]]; then
  BIND_DN="cn=${LDAP_USER},${BASE_DN}"
fi

echo "Using base DN: $BASE_DN"
echo "Using bind DN: $BIND_DN"

LDAPTLS_REQCERT=never ldapsearch -x \
  -H "ldap://127.0.0.1:$local_port" \
  -D "$BIND_DN" -w "$LDAP_PASS" \
  -b "$BASE_DN" | head
