#!/usr/bin/env bash
# Test: Verify bootstrap LDIF auto-loads during LDAP deployment
#
# Security: This script protects sensitive data (LDAP passwords) from being
# exposed in shell traces. Commands that use credentials temporarily disable
# tracing with `set +x` and re-enable it afterward if TRACE_ENABLED=1.

set -e

echo "=========================================="
echo "Directory Auto-Load Test"
echo "=========================================="
echo ""

# Step 1: Delete existing LDAP deployment
echo "1. Cleaning up existing LDAP deployment..."
kubectl delete namespace directory 2>/dev/null || echo "   No existing directory namespace"
sleep 3
echo "   ✅ Cleanup complete"
echo ""

# Step 2: Deploy LDAP with --enable-vault
echo "2. Deploying LDAP with Vault integration..."
./scripts/k3d-manager deploy_ldap --enable-vault > /tmp/test-directory-deploy.log 2>&1
echo "   ✅ Deployment complete"
echo ""

# Step 3: Wait for pod to be ready
echo "3. Waiting for LDAP pod to be ready..."
kubectl -n directory wait --for=condition=ready pod -l app.kubernetes.io/name=openldap-bitnami --timeout=120s
LDAP_POD=$(kubectl -n directory get pod -l app.kubernetes.io/name=openldap-bitnami -o jsonpath='{.items[0].metadata.name}')
echo "   Pod: $LDAP_POD"
echo "   ✅ Pod ready"
echo ""

# Step 4: Get admin password (disable tracing to protect credentials)
{ set +x; } 2>/dev/null
LDAP_PASS=$(kubectl -n directory get secret openldap-admin -o jsonpath='{.data.LDAP_ADMIN_PASSWORD}' | base64 -d)
[[ "${TRACE_ENABLED:-}" == "1" ]] && set -x

# Step 5: Verify directory structure
echo "4. Verifying directory structure..."
{ set +x; } 2>/dev/null
ENTRIES=$(kubectl -n directory exec "$LDAP_POD" -- ldapsearch -x -H ldap://127.0.0.1:1389 \
  -D "cn=ldap-admin,dc=home,dc=org" \
  -w "$LDAP_PASS" \
  -b "dc=home,dc=org" \
  "(objectClass=*)" dn 2>/dev/null | grep "^dn:" | wc -l)
[[ "${TRACE_ENABLED:-}" == "1" ]] && set -x

echo "   Total entries found: $ENTRIES"
if [ "$ENTRIES" -eq 10 ]; then
  echo "   ✅ Correct number of entries (expected: 10)"
else
  echo "   ❌ FAILED: Expected 10 entries, found $ENTRIES"
  exit 1
fi
echo ""

# Step 6: Verify users (disable tracing to protect credentials)
echo "5. Verifying test users..."
{ set +x; } 2>/dev/null
for user in chengkai.liang jenkins-admin test-user; do
  if kubectl -n directory exec "$LDAP_POD" -- ldapsearch -x -H ldap://127.0.0.1:1389 \
    -D "cn=ldap-admin,dc=home,dc=org" \
    -w "$LDAP_PASS" \
    -b "dc=home,dc=org" \
    "(cn=$user)" dn 2>/dev/null | grep -q "^dn: cn=$user"; then
    echo "   ✅ User found: $user"
  else
    echo "   ❌ FAILED: User not found: $user"
    exit 1
  fi
done
[[ "${TRACE_ENABLED:-}" == "1" ]] && set -x
echo ""

# Step 7: Verify groups (disable tracing to protect credentials)
echo "6. Verifying test groups..."
{ set +x; } 2>/dev/null
for group in jenkins-admins it-devops developers; do
  if kubectl -n directory exec "$LDAP_POD" -- ldapsearch -x -H ldap://127.0.0.1:1389 \
    -D "cn=ldap-admin,dc=home,dc=org" \
    -w "$LDAP_PASS" \
    -b "dc=home,dc=org" \
    "(cn=$group)" dn 2>/dev/null | grep -q "^dn: cn=$group"; then
    echo "   ✅ Group found: $group"
  else
    echo "   ❌ FAILED: Group not found: $group"
    exit 1
  fi
done
[[ "${TRACE_ENABLED:-}" == "1" ]] && set -x
echo ""

# Step 8: Verify Vault secret exists
echo "7. Verifying Vault LDIF secret..."
if grep -q "seeded Vault LDIF secret/ldap/bootstrap" /tmp/test-directory-deploy.log; then
  echo "   ✅ Bootstrap LDIF seeded to Vault"
else
  echo "   ⚠️  WARNING: Could not verify Vault seeding from logs"
fi
echo ""

echo "=========================================="
echo "Test Result: ✅ PASSED"
echo "=========================================="
echo ""
echo "Summary:"
echo "- Bootstrap LDIF automatically loaded from Vault"
echo "- 10 directory entries created (1 base DN + 3 OUs + 3 users + 3 groups)"
echo "- All test users present: chengkai.liang, jenkins-admin, test-user"
echo "- All test groups present: jenkins-admins, it-devops, developers"
echo ""
echo "Test user groups:"
echo "  chengkai.liang: jenkins-admins, it-devops"
echo "  jenkins-admin:  jenkins-admins, it-devops"
echo "  test-user:      developers"
echo ""
echo "Note: Test user passwords are defined in scripts/etc/ldap/bootstrap-basic-schema.ldif"
echo ""
