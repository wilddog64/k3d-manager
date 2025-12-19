#!/usr/bin/env bash
set -euo pipefail

namespace="${1:-directory}"
release="${2:-openldap}"
service="${3:-openldap-openldap-bitnami}"
local_port="${4:-3389}"

echo "Fetching admin credentials from $namespace/openldap-admin"
LDAP_USER=$(kubectl -n "$namespace" get secret openldap-admin -o jsonpath='{.data.LDAP_ADMIN_USERNAME}' | base64 -d | tr -d '\n')
LDAP_PASS=$(kubectl -n "$namespace" get secret openldap-admin -o jsonpath='{.data.LDAP_ADMIN_PASSWORD}' | base64 -d | tr -d '\n')
BASE_DN=${5:-"dc=home,dc=org"}
BIND_DN="$LDAP_USER"

if [[ "$BIND_DN" != *"="* ]]; then
  BIND_DN="cn=${LDAP_USER},${BASE_DN}"
fi

echo "Port-forwarding $namespace/$service to localhost:$local_port"
kubectl -n "$namespace" port-forward "svc/$service" "$local_port":389 >/tmp/ldap-portforward.log 2>&1 &
PF_PID=$!
sleep 3

if ! kill -0 "$PF_PID" >/dev/null 2>&1; then
  echo "Port-forward failed:" >&2
  cat /tmp/ldap-portforward.log >&2
  exit 1
fi

trap 'kill $PF_PID >/dev/null 2>&1 || true' EXIT

LDAPTLS_REQCERT=never ldapsearch -x \
  -H "ldap://127.0.0.1:$local_port" \
  -D "$BIND_DN" -w "$LDAP_PASS" \
  -b "$BASE_DN" | head
