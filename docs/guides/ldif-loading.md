# Custom LDIF File Loading - Quick Reference

## Overview

The LDAP plugin now supports loading custom LDIF files to populate OpenLDAP with any schema/structure you need.

## Usage

### Method 1: Environment Variable

```bash
# Set the path to your custom LDIF file
export LDAP_LDIF_FILE="${PWD}/scripts/etc/ldap/bootstrap-ad-schema.ldif"

# Deploy LDAP
./scripts/k3d-manager deploy_ldap
```

### Method 2: Inline

```bash
LDAP_LDIF_FILE="${PWD}/scripts/etc/ldap/bootstrap-ad-schema.ldif" \
  ./scripts/k3d-manager deploy_ldap
```

## How It Works

1. **Custom LDIF File** (if `LDAP_LDIF_FILE` is set):
   - Plugin checks if `LDAP_LDIF_FILE` environment variable is set
   - If file exists, reads content from the file
   - Stores content in Vault at `secret/ldap/bootstrap`
   - ESO syncs from Vault to Kubernetes secret
   - OpenLDAP loads LDIF on startup

2. **Default Behavior** (if `LDAP_LDIF_FILE` is NOT set):
   - Plugin generates default LDIF inline (existing behavior)
   - Creates basic structure: base DN, groups OU, service OU
   - Adds Jenkins admin user and jenkins-admins group

## Example: Deploy OpenLDAP with AD Schema

```bash
# Step 1: Set LDIF file to AD-schema template
export LDAP_LDIF_FILE="${PWD}/scripts/etc/ldap/bootstrap-ad-schema.ldif"

# Step 2: Verify file exists
ls -lh "$LDAP_LDIF_FILE"

# Step 3: Deploy OpenLDAP
./scripts/k3d-manager deploy_ldap

# Step 4: Verify AD-style structure loaded
LDAP_ADMIN_PASSWORD=$(kubectl get secret openldap-admin -n directory -o jsonpath='{.data.LDAP_ADMIN_PASSWORD}' | base64 -d)
POD_NAME=$(kubectl get pods -n directory -l app.kubernetes.io/name=openldap-bitnami -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n directory "$POD_NAME" -- \
  ldapsearch -x \
  -D "cn=admin,DC=corp,DC=example,DC=com" \
  -w "$LDAP_ADMIN_PASSWORD" \
  -b "DC=corp,DC=example,DC=com" \
  -LLL \
  "(objectClass=*)" dn

# Expected output:
# dn: DC=corp,DC=example,DC=com
# dn: OU=ServiceAccounts,DC=corp,DC=example,DC=com
# dn: OU=Users,DC=corp,DC=example,DC=com
# dn: OU=Groups,DC=corp,DC=example,DC=com
# dn: CN=Jenkins Service,OU=ServiceAccounts,DC=corp,DC=example,DC=com
# dn: CN=Alice Admin,OU=Users,DC=corp,DC=example,DC=com
# ... (more AD-style entries)
```

## Troubleshooting

### Issue: LDIF file not found

**Symptom:**
```
[ERROR] [ldap] custom LDIF file is empty: /path/to/file.ldif
```

**Solution:**
- Verify file path is correct and absolute
- Check file has read permissions
- Ensure file is not empty

### Issue: OpenLDAP has old schema after setting LDAP_LDIF_FILE

**Cause:** OpenLDAP was already deployed with old schema

**Solution:**
```bash
# Delete existing deployment
kubectl delete namespace directory --wait=true

# Redeploy with LDIF_FILE set
export LDAP_LDIF_FILE="${PWD}/scripts/etc/ldap/bootstrap-ad-schema.ldif"
./scripts/k3d-manager deploy_ldap
```

### Issue: LDAP pod fails to start

**Diagnosis:**
```bash
kubectl logs -n directory -l app.kubernetes.io/name=openldap-bitnami
```

**Common causes:**
- Invalid LDIF syntax
- Duplicate DN entries
- Missing required attributes
- Invalid objectClass values

## LDIF File Requirements

Your custom LDIF file must:

1. **Be valid LDIF syntax**
   - Each entry starts with `dn:` (distinguish name)
   - Blank line between entries
   - Attributes follow `key: value` format

2. **Include base DN**
   ```ldif
   dn: DC=corp,DC=example,DC=com
   objectClass: top
   objectClass: dcObject
   objectClass: organization
   o: Corp Example
   dc: corp
   ```

3. **Use correct objectClass for each entry type**
   - Organizations: `dcObject`, `organization`
   - OUs: `organizationalUnit`
   - Users: `inetOrgPerson`, `organizationalPerson`, `person`
   - Groups: `groupOfNames`

4. **Have proper attribute values**
   - DN components must exist as attributes (dc, ou, cn, etc.)
   - Required attributes for each objectClass
   - Valid syntax for each attribute type

## Example LDIF Files

### Minimal Example

```ldif
dn: dc=example,dc=com
objectClass: top
objectClass: dcObject
objectClass: organization
o: Example Org
dc: example

dn: ou=users,dc=example,dc=com
objectClass: top
objectClass: organizationalUnit
ou: users

dn: uid=testuser,ou=users,dc=example,dc=com
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: person
uid: testuser
cn: Test User
sn: User
userPassword: {SSHA}W6ph5Mm5Pz8GgiULbPgzG37mj9g1gLQy
```

### AD-Compatible Example

See: `scripts/etc/ldap/bootstrap-ad-schema.ldif`

## Integration with Directory Service Abstraction

When using custom LDIF with directory service providers:

```bash
# For OpenLDAP provider (default)
export DIRECTORY_SERVICE_PROVIDER=openldap
export LDAP_LDIF_FILE="${PWD}/scripts/etc/ldap/bootstrap-ad-schema.ldif"

# For Active Directory provider testing
export DIRECTORY_SERVICE_PROVIDER=activedirectory
export LDAP_LDIF_FILE="${PWD}/scripts/etc/ldap/bootstrap-ad-schema.ldif"
# AD provider will use OpenLDAP with AD schema for testing
```

## Future Enhancements

Planned features (not yet implemented):
- Smoke test for verifying LDIF loaded correctly
- LDIF validation before deployment
- Support for multiple LDIF files
- LDIF templating with variable substitution