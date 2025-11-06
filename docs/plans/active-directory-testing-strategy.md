# Active Directory Testing Strategy

**Date**: 2025-11-05
**Status**: Planned
**Related**: [Active Directory Integration](active-directory-integration.md), [Configuration-Driven Design](../architecture/configuration-driven-design.md)

---

## Overview

This document outlines the testing strategy for Active Directory integration without requiring access to a real Active Directory environment during development. The key insight is to make OpenLDAP mimic Active Directory's schema, allowing us to test the Jenkins Active Directory plugin against OpenLDAP before validating with real AD.

## The Challenge

Traditional testing approach would require:
- ❌ Access to corporate Active Directory
- ❌ VPN connectivity to enterprise network
- ❌ Multiple iterations with real AD for debugging
- ❌ Risk of breaking production authentication

## The Smart Solution: Schema Compatibility Testing

Instead of replicating AD behavior, we:
1. ✅ **Configure OpenLDAP to use AD-style schema**
2. ✅ **Use same JCasC config for both OpenLDAP and AD**
3. ✅ **Test with active-directory plugin against OpenLDAP**
4. ✅ **Switch to real AD with minimal changes**

### Key Insight

The Jenkins Active Directory plugin doesn't actually require Active Directory - it requires an LDAP server with AD-compatible schema. OpenLDAP can provide this!

## Current vs Target Schema

### Current OpenLDAP Structure

```
dc=home,dc=org                    (base DN)
├── ou=groups                     (lowercase OU)
│   └── cn=jenkins-admins
└── ou=service                    (lowercase OU)
    └── uid=jenkins-bootstrap     (uid attribute)
```

**Jenkins LDAP Plugin Config:**
```yaml
securityRealm:
  ldap:
    configurations:
      - server: "ldap://openldap.directory.svc:389"
        rootDN: "dc=home,dc=org"
        userSearchBase: "ou=service"
        groupSearchBase: "ou=groups"
```

### Target: AD-Compatible OpenLDAP Structure

```
DC=corp,DC=example,DC=com         (uppercase DC components)
├── OU=Groups                     (uppercase OU, AD-style)
│   └── CN=Jenkins Admins
└── OU=Users                      (uppercase OU, AD-style)
    └── CN=Jenkins Service        (CN attribute, AD-style)
        sAMAccountName: jenkins-svc
```

**Jenkins Active Directory Plugin Config:**
```yaml
securityRealm:
  activeDirectory:
    domains:
      - name: "corp.example.com"
        servers: "openldap.directory.svc:389"  # Points to OpenLDAP!
        bindName: "CN=Jenkins Service,OU=Users,DC=corp,DC=example,DC=com"
    groupLookupStrategy: "TOKENGROUPS"  # OpenLDAP ignores, AD uses
```

## Implementation Plan

### Phase 1: Create AD-Schema OpenLDAP LDIF

**File:** `scripts/etc/ldap/bootstrap-ad-schema.ldif`

```ldif
# Base DN (AD-style with uppercase DC)
dn: DC=corp,DC=example,DC=com
objectClass: top
objectClass: dcObject
objectClass: organization
o: Corp Example
dc: corp

# Users OU (AD-style uppercase)
dn: OU=Users,DC=corp,DC=example,DC=com
objectClass: top
objectClass: organizationalUnit
ou: Users

# Groups OU (AD-style uppercase)
dn: OU=Groups,DC=corp,DC=example,DC=com
objectClass: top
objectClass: organizationalUnit
ou: Groups

# Service Accounts OU (AD-style)
dn: OU=ServiceAccounts,DC=corp,DC=example,DC=com
objectClass: top
objectClass: organizationalUnit
ou: ServiceAccounts

# Jenkins Service Account (AD-style CN + sAMAccountName)
dn: CN=Jenkins Service,OU=ServiceAccounts,DC=corp,DC=example,DC=com
objectClass: top
objectClass: person
objectClass: inetOrgPerson
objectClass: organizationalPerson
cn: Jenkins Service
sn: Service
givenName: Jenkins
displayName: Jenkins Service Account
sAMAccountName: jenkins-svc
userPrincipalName: jenkins-svc@corp.example.com
mail: jenkins-svc@corp.example.com
userPassword: {SSHA}...

# Test User (AD-style)
dn: CN=John Doe,OU=Users,DC=corp,DC=example,DC=com
objectClass: top
objectClass: person
objectClass: inetOrgPerson
objectClass: organizationalPerson
cn: John Doe
sn: Doe
givenName: John
displayName: John Doe
sAMAccountName: jdoe
userPrincipalName: jdoe@corp.example.com
mail: jdoe@corp.example.com
userPassword: {SSHA}...

# Jenkins Admins Group (AD-style)
dn: CN=Jenkins Admins,OU=Groups,DC=corp,DC=example,DC=com
objectClass: top
objectClass: groupOfNames
cn: Jenkins Admins
description: Jenkins Administrators
member: CN=Jenkins Service,OU=ServiceAccounts,DC=corp,DC=example,DC=com
member: CN=John Doe,OU=Users,DC=corp,DC=example,DC=com

# IT Developers Group (nested group test)
dn: CN=IT Developers,OU=Groups,DC=corp,DC=example,DC=com
objectClass: top
objectClass: groupOfNames
cn: IT Developers
description: IT Development Team
member: CN=Jenkins Admins,OU=Groups,DC=corp,DC=example,DC=com
```

### Phase 2: Configure OpenLDAP with AD Schema

**Variables:** `scripts/etc/ldap/vars-ad-schema.sh`

```bash
# AD-compatible configuration
export LDAP_DC_PRIMARY=corp
export LDAP_DC_SECONDARY=example
export LDAP_DC_TERTIARY=com
export LDAP_BASE_DN="DC=corp,DC=example,DC=com"
export LDAP_DOMAIN="corp.example.com"

# Use AD-style OUs (uppercase)
export LDAP_GROUP_OU="OU=Groups"
export LDAP_SERVICE_OU="OU=ServiceAccounts"
export LDAP_USER_OU="OU=Users"

# AD-style bind DN
export LDAP_BINDDN="CN=Jenkins Service,OU=ServiceAccounts,DC=corp,DC=example,DC=com"

# AD-style group DN
export LDAP_JENKINS_GROUP="CN=Jenkins Admins,OU=Groups,DC=corp,DC=example,DC=com"

# Use custom LDIF with AD schema
export LDAP_LDIF_PATH="scripts/etc/ldap/bootstrap-ad-schema.ldif"
```

### Phase 3: Deploy OpenLDAP with AD Schema

```bash
# Load AD-compatible configuration
source scripts/etc/ldap/vars-ad-schema.sh

# Deploy OpenLDAP with AD schema
./scripts/k3d-manager deploy_ldap

# Verify AD-style structure
kubectl exec -n directory openldap-openldap-bitnami-0 -- \
  ldapsearch -x -b "DC=corp,DC=example,DC=com" \
  -D "CN=Jenkins Service,OU=ServiceAccounts,DC=corp,DC=example,DC=com" \
  -w "${LDAP_ADMIN_PASSWORD}" \
  "(objectClass=*)"
```

### Phase 4: Test with Active Directory Plugin Against OpenLDAP

```bash
# Configure AD provider to point at OpenLDAP
export DIRECTORY_SERVICE_PROVIDER=activedirectory
export AD_DOMAIN=corp.example.com
export AD_SERVERS=openldap.directory.svc:389
export AD_BASE_DN="DC=corp,DC=example,DC=com"
export AD_BIND_DN="CN=Jenkins Service,OU=ServiceAccounts,DC=corp,DC=example,DC=com"
export AD_BIND_PASSWORD="${LDAP_ADMIN_PASSWORD}"
export AD_USER_SEARCH_BASE="OU=Users,DC=corp,DC=example,DC=com"
export AD_GROUP_SEARCH_BASE="OU=Groups,DC=corp,DC=example,DC=com"
export AD_USE_SSL=0  # OpenLDAP test instance without TLS

# Deploy Jenkins with Active Directory provider
./scripts/k3d-manager deploy_jenkins --enable-ldap

# Result: Jenkins uses Active Directory plugin but queries OpenLDAP
```

### Phase 5: Verify Authentication and Authorization

```bash
# Test 1: Check Jenkins uses Active Directory plugin
kubectl logs -n jenkins deploy/jenkins | grep -i "active.*directory"

# Test 2: Verify JCasC configuration
kubectl exec -n jenkins deploy/jenkins -- cat /var/jenkins_home/jenkins.yaml \
  | grep -A 20 "securityRealm"

# Test 3: Test login with AD-schema user
# - Open Jenkins UI: http://jenkins.dev.local.me
# - Login with: jdoe / password
# - Verify user sees "John Doe" display name
# - Verify user has admin permissions (from Jenkins Admins group)

# Test 4: Verify group membership
kubectl exec -n jenkins deploy/jenkins -- \
  java -jar /usr/share/jenkins/jenkins-cli.jar -s http://localhost:8080 \
  -auth jdoe:password who-am-i
```

### Phase 6: Switch to Real Active Directory

```bash
# Minimal changes - just point at real AD servers
export AD_SERVERS=dc1.corp.example.com:636
export AD_USE_SSL=1
export AD_TLS_CONFIG=JDK_TRUSTSTORE  # Or custom CA bundle

# Re-deploy Jenkins (JCasC config stays the same!)
./scripts/k3d-manager deploy_jenkins --enable-ldap

# Test with real AD users
# Everything else is identical!
```

## Testing Matrix

### What Can Be Tested (OpenLDAP with AD Schema)

| Feature | OpenLDAP Test | Real AD | Notes |
|---------|--------------|---------|-------|
| **Basic Authentication** | ✅ Full | ✅ Full | Same LDAP bind mechanism |
| **Group Membership** | ✅ Full | ✅ Full | Both support memberOf |
| **Nested Groups** | ⚠️ Partial | ✅ Full | OpenLDAP: recursive queries, AD: TOKENGROUPS |
| **DN Format** | ✅ Full | ✅ Full | Both use CN=name,OU=org,DC=domain |
| **sAMAccountName** | ✅ Full | ✅ Full | Can add to OpenLDAP schema |
| **userPrincipalName** | ✅ Full | ✅ Full | Can add to OpenLDAP schema |
| **Display Names** | ✅ Full | ✅ Full | Both support cn/displayName |
| **Email Attributes** | ✅ Full | ✅ Full | Both support mail attribute |
| **TLS/LDAPS** | ✅ Full | ✅ Full | OpenLDAP supports LDAPS on port 636 |
| **Multiple DCs** | ❌ No | ✅ Full | OpenLDAP single server only |
| **Kerberos SSO** | ❌ No | ✅ Full | Requires real AD |
| **Global Catalog** | ❌ No | ✅ Full | AD-specific feature |
| **tokenGroups Attribute** | ❌ No | ✅ Full | AD-specific optimization |

### Expected Behavior Differences

**Features that work differently but are non-blocking:**

1. **Nested Groups**
   - OpenLDAP: Plugin does recursive LDAP queries (slower but works)
   - AD: Plugin uses TOKENGROUPS attribute (faster)
   - **Impact:** Performance only, functionality identical

2. **Multi-Domain Controllers**
   - OpenLDAP: Single server
   - AD: Multiple DCs with failover
   - **Impact:** Can't test failover, but connection logic is same

3. **Kerberos Authentication**
   - OpenLDAP: Not supported
   - AD: Can use Kerberos tickets
   - **Impact:** Simple bind works for both, Kerberos is optional

### Validation Checklist

**After OpenLDAP Testing:**
- [ ] Jenkins deploys without errors
- [ ] JCasC shows `activeDirectory` security realm (not `ldap`)
- [ ] Can login with test user (jdoe)
- [ ] User display name shown correctly (John Doe)
- [ ] Group membership detected (Jenkins Admins)
- [ ] Authorization works (admin permissions granted)
- [ ] Can create and run jobs
- [ ] User profile shows correct email

**After Real AD Testing:**
- [ ] Connection to real DC succeeds
- [ ] TLS/LDAPS certificate validation works
- [ ] Real AD users can login
- [ ] Real AD groups map correctly
- [ ] Nested groups resolve properly (via TOKENGROUPS)
- [ ] Multiple DC failover works (if configured)
- [ ] No errors in Jenkins logs

## Advantages of This Approach

### High Confidence Testing
✅ **Same plugin** - Tests actual active-directory plugin, not ldap plugin
✅ **Same schema** - DN structure matches real AD
✅ **Same JCasC** - Configuration file identical between test and production
✅ **Same queries** - LDAP search filters identical

### Development Velocity
✅ **No VPN required** - Test locally without corporate network
✅ **Fast iteration** - Can restart OpenLDAP in seconds
✅ **Easy debugging** - Full access to LDAP server logs
✅ **Reproducible** - Anyone can run tests without AD access

### Risk Mitigation
✅ **Proven format** - Uses baseline-compatible JCasC structure
✅ **Gradual migration** - Can deploy to test environment first
✅ **Easy rollback** - Keep OpenLDAP provider as fallback
✅ **Clear comparison** - Can A/B test OpenLDAP vs AD side-by-side

## Known Limitations

### What Can't Be Tested

**TOKENGROUPS Optimization**
- **Limitation:** OpenLDAP doesn't have tokenGroups binary attribute
- **Impact:** Nested group resolution slower (but still works via recursive queries)
- **Mitigation:** Document performance difference, verify with real AD

**Kerberos SSO**
- **Limitation:** OpenLDAP doesn't support Kerberos authentication
- **Impact:** Can't test SSO login flow
- **Mitigation:** Simple bind authentication proven to work, Kerberos is bonus feature

**Multi-Domain Failover**
- **Limitation:** OpenLDAP is single server
- **Impact:** Can't test DC failover logic
- **Mitigation:** Connection code same for single or multiple servers

**Global Catalog Queries**
- **Limitation:** OpenLDAP doesn't have Global Catalog port (3268/3269)
- **Impact:** Can't test cross-domain queries
- **Mitigation:** Single-domain authentication works identically

## Implementation Checklist

### Development Phase
- [ ] Create `scripts/etc/ldap/bootstrap-ad-schema.ldif`
- [ ] Create `scripts/etc/ldap/vars-ad-schema.sh`
- [ ] Implement AD provider (`scripts/lib/dirservices/activedirectory.sh`)
- [ ] Add AD schema configuration documentation
- [ ] Update LDAP plugin to support AD-schema mode

### Testing Phase
- [ ] Deploy OpenLDAP with AD schema
- [ ] Verify DN structure matches AD format
- [ ] Deploy Jenkins with active-directory provider
- [ ] Test authentication with AD-schema users
- [ ] Test group membership and authorization
- [ ] Test nested groups (if configured)
- [ ] Document any differences from baseline AD

### Production Phase
- [ ] Document configuration for real AD
- [ ] Provide example AD_SERVERS values
- [ ] Add TLS certificate configuration guide
- [ ] Create troubleshooting guide for AD-specific issues
- [ ] Add monitoring/alerting recommendations

## Success Criteria

**Phase 1 Complete (OpenLDAP Testing):**
- Jenkins deploys with active-directory plugin
- Authentication works against OpenLDAP with AD schema
- Group-based authorization functions correctly
- All test cases pass
- Documentation is complete

**Phase 2 Complete (Real AD Validation):**
- Connection to production AD succeeds
- Real users can authenticate
- Group membership resolves correctly (including nested groups)
- Performance is acceptable
- No errors in production logs

## Related Documentation

- [Active Directory Integration Plan](active-directory-integration.md) - Overall AD implementation plan
- [Directory Service Interface](directory-service-interface.md) - Provider interface specification
- [Configuration-Driven Design](../architecture/configuration-driven-design.md) - Architecture principles
- [CLAUDE.md](../../CLAUDE.md) - Project guidelines
