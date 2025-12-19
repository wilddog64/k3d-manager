# Active Directory Provider Testing Instructions

**Date**: 2025-11-06
**Purpose**: Step-by-step instructions for testing the Active Directory provider implementation using OpenLDAP with AD-compatible schema

---

## Overview

This guide will walk you through testing the Active Directory provider implementation **without requiring access to a real Active Directory environment**. The key approach is to use OpenLDAP configured with an AD-compatible schema, allowing the Jenkins Active Directory plugin to be tested locally.

## Prerequisites

Before starting, ensure you have:

- ✅ k3d cluster running (or ready to create)
- ✅ Vault deployed and unsealed
- ✅ External Secrets Operator (ESO) deployed
- ✅ No existing Jenkins or OpenLDAP deployments (clean slate)

## Testing Phases

### Phase 1: Deploy OpenLDAP with AD Schema

**Step 1.1: Configure LDAP with AD-compatible schema**

```bash
# Set LDAP configuration to use AD-schema LDIF
export LDAP_LDIF_PATH="${PWD}/scripts/etc/ldap/bootstrap-ad-schema.ldif"

# Verify the LDIF file exists
ls -lh "${LDAP_LDIF_PATH}"
# Should show: scripts/etc/ldap/bootstrap-ad-schema.ldif
```

**Step 1.2: Deploy OpenLDAP**

```bash
# Deploy OpenLDAP with the AD schema
./scripts/k3d-manager deploy_ldap

# Wait for OpenLDAP to be ready (may take 1-2 minutes)
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=openldap-bitnami -n directory --timeout=300s
```

**Step 1.3: Verify AD-schema structure**

```bash
# Get the OpenLDAP admin password
LDAP_ADMIN_PASSWORD=$(kubectl get secret openldap-admin -n directory -o jsonpath='{.data.LDAP_ADMIN_PASSWORD}' | base64 -d)

# Get the pod name (dynamic deployment name)
POD_NAME=$(kubectl get pods -n directory -l app.kubernetes.io/name=openldap-bitnami -o jsonpath='{.items[0].metadata.name}')

# Test LDAP connection with AD-style DN
kubectl exec -n directory "$POD_NAME" -- \
  ldapsearch -x \
  -D "cn=admin,DC=corp,DC=example,DC=com" \
  -w "${LDAP_ADMIN_PASSWORD}" \
  -b "DC=corp,DC=example,DC=com" \
  -LLL \
  "(objectClass=*)" dn

# Expected output should show AD-style DNs:
# dn: DC=corp,DC=example,DC=com
# dn: OU=ServiceAccounts,DC=corp,DC=example,DC=com
# dn: OU=Users,DC=corp,DC=example,DC=com
# dn: OU=Groups,DC=corp,DC=example,DC=com
# dn: CN=Jenkins Service,OU=ServiceAccounts,DC=corp,DC=example,DC=com
# dn: CN=Alice Admin,OU=Users,DC=corp,DC=example,DC=com
# dn: CN=Bob Developer,OU=Users,DC=corp,DC=example,DC=com
# dn: CN=Charlie User,OU=Users,DC=corp,DC=example,DC=com
# dn: CN=Jenkins Admins,OU=Groups,DC=corp,DC=example,DC=com
# dn: CN=IT Developers,OU=Groups,DC=corp,DC=example,DC=com
# dn: CN=IT Users,OU=Groups,DC=corp,DC=example,DC=com
```

**Step 1.4: Verify test users**

```bash
# Check Alice (admin user)
kubectl exec -n directory openldap-openldap-bitnami-0 -- \
  ldapsearch -x \
  -D "CN=Jenkins Service,OU=ServiceAccounts,DC=corp,DC=example,DC=com" \
  -w "${LDAP_ADMIN_PASSWORD}" \
  -b "OU=Users,DC=corp,DC=example,DC=com" \
  -LLL \
  "(sAMAccountName=alice)" \
  cn sAMAccountName mail memberOf

# Expected output:
# dn: CN=Alice Admin,OU=Users,DC=corp,DC=example,DC=com
# cn: Alice Admin
# sAMAccountName: alice
# mail: alice@corp.example.com
```

**Step 1.5: Verify groups**

```bash
# Check Jenkins Admins group
kubectl exec -n directory openldap-openldap-bitnami-0 -- \
  ldapsearch -x \
  -D "CN=Jenkins Service,OU=ServiceAccounts,DC=corp,DC=example,DC=com" \
  -w "${LDAP_ADMIN_PASSWORD}" \
  -b "OU=Groups,DC=corp,DC=example,DC=com" \
  -LLL \
  "(cn=Jenkins Admins)" \
  cn member

# Expected output:
# dn: CN=Jenkins Admins,OU=Groups,DC=corp,DC=example,DC=com
# cn: Jenkins Admins
# member: CN=Jenkins Service,OU=ServiceAccounts,DC=corp,DC=example,DC=com
# member: CN=Alice Admin,OU=Users,DC=corp,DC=example,DC=com
```

✅ **Phase 1 Success Criteria:**
- OpenLDAP deployed and running
- AD-style DNs visible (uppercase OU, CN attributes)
- Test users exist with sAMAccountName attribute
- Groups exist with proper member attributes

---

### Phase 2: Configure Active Directory Provider

**Step 2.1: Set AD provider configuration**

```bash
# Configure directory service provider
export DIRECTORY_SERVICE_PROVIDER=activedirectory

# AD domain configuration
export AD_DOMAIN=corp.example.com
export AD_BASE_DN="DC=corp,DC=example,DC=com"

# Point AD provider at OpenLDAP service (using plain LDAP for testing)
export AD_SERVERS=openldap.directory.svc.cluster.local
export AD_PORT=389
export AD_USE_SSL=0  # OpenLDAP test instance without TLS

# Service account credentials (from OpenLDAP)
export AD_BIND_DN="CN=Jenkins Service,OU=ServiceAccounts,DC=corp,DC=example,DC=com"
export AD_BIND_PASSWORD="${LDAP_ADMIN_PASSWORD}"

# Search bases
export AD_USER_SEARCH_BASE="OU=Users,DC=corp,DC=example,DC=com"
export AD_GROUP_SEARCH_BASE="OU=Groups,DC=corp,DC=example,DC=com"

# Enable test mode (bypasses connectivity validation if ldapsearch not available)
export AD_TEST_MODE=1

# Display configuration for verification
echo "=== Active Directory Provider Configuration ==="
echo "Provider: ${DIRECTORY_SERVICE_PROVIDER}"
echo "Domain: ${AD_DOMAIN}"
echo "Servers: ${AD_SERVERS}"
echo "Port: ${AD_PORT}"
echo "Base DN: ${AD_BASE_DN}"
echo "Bind DN: ${AD_BIND_DN}"
echo "User Search Base: ${AD_USER_SEARCH_BASE}"
echo "Group Search Base: ${AD_GROUP_SEARCH_BASE}"
echo "Test Mode: ${AD_TEST_MODE}"
echo "================================================"
```

**Step 2.2: Verify AD provider is loaded**

```bash
# Check that AD provider functions are available
source scripts/lib/dirservices/activedirectory.sh

# Test configuration display
_dirservice_activedirectory_config

# Expected output:
# [INFO] [dirservice:activedirectory] configuration:
#   Domain: corp.example.com
#   Servers: openldap.directory.svc.cluster.local
#   Base DN: DC=corp,DC=example,DC=com
#   Bind DN: CN=Jenkins Service,OU=ServiceAccounts,DC=corp,DC=example,DC=com
#   Use SSL: 0
#   Port: 389
#   ...
```

✅ **Phase 2 Success Criteria:**
- All AD environment variables set correctly
- AD provider configuration displays without errors
- Provider points at OpenLDAP service

---

### Phase 3: Deploy Jenkins with Active Directory Provider

**Step 3.1: Deploy Jenkins**

```bash
# Deploy Jenkins with AD provider
# The deploy_jenkins function should detect DIRECTORY_SERVICE_PROVIDER=activedirectory
./scripts/k3d-manager deploy_jenkins --enable-ldap

# Monitor deployment
kubectl rollout status deployment/jenkins -n jenkins --timeout=600s
```

**Step 3.2: Check Jenkins logs for AD plugin initialization**

```bash
# Look for Active Directory plugin initialization
kubectl logs -n jenkins deployment/jenkins --tail=100 | grep -i "active.*directory"

# Expected patterns:
# - "Active Directory plugin"
# - "ActiveDirectorySecurityRealm"
# - No error messages about AD connectivity
```

**Step 3.3: Verify JCasC configuration**

```bash
# Check the generated JCasC security realm configuration
kubectl exec -n jenkins deployment/jenkins -- cat /var/jenkins_home/jenkins.yaml | grep -A 20 "securityRealm"

# Expected output should show:
# securityRealm:
#   activeDirectory:
#     bindPassword: "${file:/vault/secrets/ad-ldap-bind-password}"
#     cache:
#       size: 50
#       ttl: 3600
#     customDomain: true
#     domains:
#       - bindName: "${file:/vault/secrets/ad-ldap-bind-username}"
#         bindPassword: "${file:/vault/secrets/ad-ldap-bind-password}"
#         name: "corp.example.com"
#         tlsConfiguration: "JDK_TRUSTSTORE"
#     groupLookupStrategy: "TOKENGROUPS"
#     requireTLS: true
```

**Step 3.4: Verify Vault secrets**

```bash
# Check that AD credentials were stored in Vault
kubectl exec -n vault vault-0 -- vault kv get secret/ad/service-accounts/jenkins-admin

# Expected output:
# ====== Data ======
# Key         Value
# ---         -----
# domain      corp.example.com
# password    <password>
# servers     openldap.directory.svc.cluster.local
# username    CN=Jenkins Service,OU=ServiceAccounts,DC=corp,DC=example,DC=com
```

**Step 3.5: Verify Vault secrets mounted in Jenkins pod**

```bash
# Check that Vault Agent injected the secrets as files
kubectl exec -n jenkins deployment/jenkins -- ls -la /vault/secrets/

# Expected files:
# ad-ldap-bind-username
# ad-ldap-bind-password

# Verify content (username should be visible, password will be present)
kubectl exec -n jenkins deployment/jenkins -- cat /vault/secrets/ad-ldap-bind-username
# Expected: CN=Jenkins Service,OU=ServiceAccounts,DC=corp,DC=example,DC=com
```

✅ **Phase 3 Success Criteria:**
- Jenkins deployed successfully
- JCasC shows `activeDirectory` (not `ldap`) security realm
- Vault contains AD credentials
- Vault Agent mounted credentials as files in Jenkins pod
- No errors in Jenkins logs

---

### Phase 4: Test Authentication

**Step 4.1: Access Jenkins UI**

```bash
# Get Jenkins URL
echo "Jenkins URL: http://jenkins.dev.local.me"

# Get the initial admin password (for fallback/comparison)
JENKINS_ADMIN_PASSWORD=$(kubectl get secret jenkins -n jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d)
echo "Fallback admin password: ${JENKINS_ADMIN_PASSWORD}"
```

**Step 4.2: Test login with AD-schema user (Alice - Admin)**

1. Open browser to `http://jenkins.dev.local.me`
2. Login with:
   - Username: `alice`
   - Password: `password` (from LDIF file)
3. **Expected Result:**
   - Login succeeds
   - User sees "Alice Admin" as display name
   - User has full administrative access

**Step 4.3: Test login with AD-schema user (Bob - Developer)**

1. Logout from Jenkins
2. Login with:
   - Username: `bob`
   - Password: `password`
3. **Expected Result:**
   - Login succeeds
   - User sees "Bob Developer" as display name
   - User has appropriate permissions (member of IT Developers group)

**Step 4.4: Test login with AD-schema user (Charlie - Read-only)**

1. Logout from Jenkins
2. Login with:
   - Username: `charlie`
   - Password: `password`
3. **Expected Result:**
   - Login succeeds
   - User sees "Charlie User" as display name
   - User has read-only access

**Step 4.5: Test login failure with invalid credentials**

1. Logout from Jenkins
2. Attempt login with:
   - Username: `alice`
   - Password: `wrongpassword`
3. **Expected Result:**
   - Login fails with authentication error
   - Error message indicates invalid credentials

**Step 4.6: Test login with fallback admin account**

1. Logout from Jenkins
2. Login with:
   - Username: `admin` (or value of `${JENKINS_ADMIN_USER}`)
   - Password: `${JENKINS_ADMIN_PASSWORD}` (from secret)
3. **Expected Result:**
   - Login succeeds (internal user database fallback)
   - User has full administrative access

✅ **Phase 4 Success Criteria:**
- Alice can login and has admin permissions
- Bob can login and has developer permissions
- Charlie can login and has read-only permissions
- Invalid credentials are rejected
- Fallback admin account still works

---

### Phase 5: Test Group Membership and Authorization

**Step 5.1: Verify user's group memberships (CLI)**

```bash
# Check Alice's groups (should include Jenkins Admins)
source scripts/lib/dirservices/activedirectory.sh
_dirservice_activedirectory_get_groups alice

# Expected output:
# CN=Jenkins Admins,OU=Groups,DC=corp,DC=example,DC=com

# Check Bob's groups (should include IT Developers)
_dirservice_activedirectory_get_groups bob

# Expected output:
# CN=IT Developers,OU=Groups,DC=corp,DC=example,DC=com
```

**Step 5.2: Verify group-based permissions in Jenkins UI**

1. Login as Alice (admin)
2. Navigate to "Manage Jenkins" → "Manage Users"
3. Click on "alice" user
4. Check "Groups" section
5. **Expected Result:**
   - Groups show: "Jenkins Admins"
   - May also show nested groups if recursive lookup works

**Step 5.3: Test group-based authorization**

1. Login as Alice (Jenkins Admins member)
2. Try to:
   - Create a new job ✅ (should succeed)
   - Configure Jenkins settings ✅ (should succeed)
   - Manage plugins ✅ (should succeed)
3. Logout and login as Charlie (IT Users member)
4. Try to:
   - View jobs ✅ (should succeed)
   - Create a new job ❌ (should fail - read-only)
   - Configure Jenkins settings ❌ (should fail - read-only)

**Step 5.4: Test nested group membership (Bob → IT Developers → Jenkins Admins)**

Note: This tests whether OpenLDAP's recursive group lookup works.

1. Check the LDIF structure:
   - IT Developers group has member: `CN=Jenkins Admins,OU=Groups,DC=corp,DC=example,DC=com`
   - Jenkins Admins group has member: `CN=Alice Admin,OU=Users,DC=corp,DC=example,DC=com`
2. Login as Bob
3. Bob is direct member of IT Developers
4. Bob should inherit permissions from Jenkins Admins (if nested groups work)
5. **Expected Result:**
   - If nested groups work: Bob has admin-level permissions
   - If nested groups don't work: Bob has only IT Developers permissions
   - Either way is acceptable for initial testing (nested groups are AD optimization)

✅ **Phase 5 Success Criteria:**
- Users' group memberships are detected correctly
- Group-based authorization works (admins can manage, users can read)
- Nested groups are handled (even if via recursive queries instead of TOKENGROUPS)

---

## Troubleshooting Common Issues

### Issue 1: Jenkins shows LDAP plugin instead of Active Directory plugin

**Symptom:** JCasC shows `securityRealm: ldap:` instead of `securityRealm: activeDirectory:`

**Diagnosis:**
```bash
# Check DIRECTORY_SERVICE_PROVIDER
echo $DIRECTORY_SERVICE_PROVIDER
# Should show: activedirectory

# Check which provider was used
kubectl exec -n jenkins deployment/jenkins -- cat /var/jenkins_home/jenkins.yaml | grep -B2 -A10 securityRealm
```

**Fix:**
```bash
# Re-export AD provider and re-deploy
export DIRECTORY_SERVICE_PROVIDER=activedirectory
./scripts/k3d-manager deploy_jenkins --enable-ldap
```

---

### Issue 2: Jenkins cannot connect to OpenLDAP

**Symptom:** Jenkins logs show "Connection refused" or "Unknown host"

**Diagnosis:**
```bash
# Test DNS resolution from Jenkins pod
kubectl exec -n jenkins deployment/jenkins -- nslookup openldap.directory.svc.cluster.local

# Test LDAP connectivity from Jenkins pod
kubectl exec -n jenkins deployment/jenkins -- nc -zv openldap.directory.svc.cluster.local 389
```

**Fix:**
```bash
# Verify OpenLDAP service exists
kubectl get svc -n directory

# Verify OpenLDAP is running
kubectl get pods -n directory

# If OpenLDAP is not running, re-deploy
./scripts/k3d-manager deploy_ldap
```

---

### Issue 3: Authentication fails for test users

**Symptom:** Login with alice/password fails

**Diagnosis:**
```bash
# Test LDAP bind with test user credentials
kubectl exec -n directory openldap-openldap-bitnami-0 -- \
  ldapsearch -x \
  -D "CN=Alice Admin,OU=Users,DC=corp,DC=example,DC=com" \
  -w "password" \
  -b "DC=corp,DC=example,DC=com" \
  -LLL \
  "(objectClass=*)" dn

# If this fails, check the LDIF was loaded correctly
kubectl exec -n directory openldap-openldap-bitnami-0 -- \
  ldapsearch -x \
  -D "cn=admin,dc=directory,dc=svc" \
  -w "${LDAP_ADMIN_PASSWORD}" \
  -b "DC=corp,DC=example,DC=com" \
  -LLL \
  "(sAMAccountName=alice)"
```

**Fix:**
```bash
# If LDIF wasn't loaded, check LDAP_LDIF_PATH was set before deploy
export LDAP_LDIF_PATH="${PWD}/scripts/etc/ldap/bootstrap-ad-schema.ldif"
kubectl delete namespace directory
./scripts/k3d-manager deploy_ldap
```

---

### Issue 4: Vault secrets not mounted in Jenkins

**Symptom:** `/vault/secrets/ad-ldap-bind-username` file not found

**Diagnosis:**
```bash
# Check Vault Agent annotations on Jenkins deployment
kubectl get deployment jenkins -n jenkins -o yaml | grep -A10 "vault.hashicorp.com"

# Check Vault Agent injector logs
kubectl logs -n vault -l app.kubernetes.io/name=vault-agent-injector
```

**Fix:**
```bash
# Ensure Vault is unsealed
kubectl exec -n vault vault-0 -- vault status

# Re-deploy Jenkins to trigger Vault Agent injection
kubectl rollout restart deployment/jenkins -n jenkins
```

---

### Issue 5: Group membership not detected

**Symptom:** User can login but doesn't have expected permissions

**Diagnosis:**
```bash
# Check user's memberOf attribute
kubectl exec -n directory openldap-openldap-bitnami-0 -- \
  ldapsearch -x \
  -D "CN=Jenkins Service,OU=ServiceAccounts,DC=corp,DC=example,DC=com" \
  -w "${LDAP_ADMIN_PASSWORD}" \
  -b "OU=Users,DC=corp,DC=example,DC=com" \
  -LLL \
  "(sAMAccountName=alice)" \
  memberOf

# Check group membership from Jenkins perspective
kubectl logs -n jenkins deployment/jenkins | grep -i "group" | tail -20
```

**Fix:**
```bash
# OpenLDAP might need memberOf overlay enabled
# This is typically handled by the Bitnami chart, but verify:
kubectl exec -n directory openldap-openldap-bitnami-0 -- \
  ldapsearch -x -LLL -s base -b "cn=config" olcDatabase | grep memberof
```

---

## What to Report

If you encounter issues during testing, please report:

1. **Which phase failed:** (Phase 1-5)
2. **Specific step that failed:** (e.g., "Step 4.2 - Test login with Alice")
3. **Error messages:** (exact error text from UI or logs)
4. **Diagnostic output:**
   ```bash
   # Include output from these commands
   kubectl get pods -A
   kubectl logs -n jenkins deployment/jenkins --tail=50
   kubectl logs -n directory openldap-openldap-bitnami-0 --tail=50
   echo $DIRECTORY_SERVICE_PROVIDER
   ```
5. **Environment details:**
   - Operating system (macOS/Linux)
   - k3d version: `k3d version`
   - kubectl version: `kubectl version --client`

---

## Success Indicators

If all phases pass, you should see:

✅ OpenLDAP running with AD-schema structure
✅ AD provider configuration validated
✅ Jenkins deployed with Active Directory plugin (not LDAP plugin)
✅ JCasC shows `activeDirectory` security realm
✅ Vault contains AD credentials
✅ Alice can login with admin permissions
✅ Bob can login with developer permissions
✅ Charlie can login with read-only permissions
✅ Group memberships detected correctly
✅ Authorization works based on group membership
✅ No errors in Jenkins logs related to AD/LDAP

---

## Next Steps After Successful Testing

Once all testing phases pass:

1. **Report success:** Confirm to Claude that all tests passed
2. **Review implementation:** Review the three implementation files:
   - `scripts/etc/ad/vars.sh`
   - `scripts/lib/dirservices/activedirectory.sh`
   - `scripts/etc/ldap/bootstrap-ad-schema.ldif`
3. **Commit changes:** After confirmation, commit the AD provider implementation
4. **Real AD testing:** (Optional) Test with real Active Directory environment:
   ```bash
   export AD_SERVERS=dc1.corp.example.com:636
   export AD_USE_SSL=1
   export AD_TEST_MODE=0
   ./scripts/k3d-manager deploy_jenkins --enable-ldap
   ```

---

## Clean Up (Optional)

To reset the environment for re-testing:

```bash
# Remove Jenkins deployment
kubectl delete namespace jenkins

# Remove OpenLDAP deployment
kubectl delete namespace directory

# Remove Vault secrets (optional)
kubectl exec -n vault vault-0 -- vault kv delete secret/ad/service-accounts/jenkins-admin

# Start fresh
./scripts/k3d-manager deploy_ldap  # with LDAP_LDIF_PATH set
./scripts/k3d-manager deploy_jenkins --enable-ldap  # with AD provider configured
```

---

**End of Testing Instructions**
