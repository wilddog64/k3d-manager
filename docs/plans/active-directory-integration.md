# Active Directory Integration Plan

**Date**: 2025-11-05
**Status**: Planned
**Related**: [Directory Service Interface](directory-service-interface.md), [Configuration-Driven Design](../architecture/configuration-driven-design.md)

---

## Overview

Active Directory (AD) integration for k3d-manager will provide enterprise authentication for Jenkins deployments. Unlike OpenLDAP (which is deployed locally), Active Directory is a **remote directory service** that connects to existing corporate infrastructure.

## Key Differences: Active Directory vs OpenLDAP

| Aspect | OpenLDAP | Active Directory |
|--------|----------|------------------|
| **Deployment** | Yes (Helm chart in cluster) | No (external infrastructure) |
| **Location** | In-cluster (k8s service) | Remote (corporate network) |
| **Protocol** | Standard LDAP (RFC 4511) | LDAP + Microsoft extensions |
| **Ports** | 389 (LDAP), 636 (LDAPS) | 389/636 + 3268/3269 (Global Catalog) |
| **Authentication** | Simple bind | Simple bind + Kerberos |
| **Group Resolution** | Flat `memberOf` queries | Nested groups + `tokenGroups` attribute |
| **Jenkins Plugin** | `ldap` | `active-directory` |
| **Use Case** | Development/testing | Production/corporate |
| **Mac Compatible** | Yes (via k3d/Docker) | Yes (remote connection via VPN) |
| **Bootstrap Required** | Yes (LDIF seed data) | No (pre-existing users/groups) |

## Design Principles

### 1. Remote Connection Mode
- AD is **never deployed** - it's external infrastructure
- Focus on **connectivity validation** before configuration
- Provide **clear error messages** for unreachable AD servers
- Support **multiple domain controllers** for failover

### 2. Mac Compatibility
For Mac users (who don't have local AD):
- **Corporate laptops**: Connected via Kerberos/network
- **VPN scenarios**: Intermittent AD access
- **Configuration-first**: Validate connectivity before proceeding

### 3. Configuration-Driven
Uses environment variables for all settings (no code changes):

```bash
AD_DOMAIN=corp.example.com
AD_SERVERS=dc1.corp.example.com,dc2.corp.example.com
AD_BIND_DN=CN=svc-jenkins,OU=ServiceAccounts,DC=corp,DC=example,DC=com
AD_BIND_PASSWORD=SecurePassword123
```

## Implementation Plan

### Phase 1: AD Provider Module (2-3 hours)

**File**: `scripts/lib/dirservices/activedirectory.sh`

Implement provider interface:

```bash
_dirservice_activedirectory_init()
  - NO deployment (AD is external)
  - Validate AD connectivity (ldapsearch test)
  - Verify service account credentials
  - Test group membership queries

_dirservice_activedirectory_create_credentials()
  - Store AD credentials in Vault
  - Format: username, password, domain, servers

_dirservice_activedirectory_generate_jcasc()
  - Generate Jenkins Active Directory plugin config
  - Use 'active-directory' plugin (not 'ldap')
  - Configure nested group resolution (TOKENGROUPS)
  - Support TLS requirements

_dirservice_activedirectory_generate_env_vars()
  - AD_DOMAIN, AD_SERVERS, AD_BIND_DN, AD_BIND_PASSWORD
  - Support multiple DCs (comma-separated)
  - Default to LDAPS (port 636)

_dirservice_activedirectory_validate_config()
  - Test LDAPS connectivity (port 636 or 3269 for GC)
  - Validate service account bind
  - Verify user/group read permissions
  - Test nested group resolution

_dirservice_activedirectory_get_groups()
  - Query user groups including nested memberships
  - Use tokenGroups attribute (AD optimization)

_dirservice_activedirectory_generate_authz()
  - Map AD groups to Jenkins permissions
  - Support domain-qualified groups: DOMAIN\GroupName

_dirservice_activedirectory_smoke_test_login()
  - Test Jenkins login with AD credentials
  - Verify group-based authorization
```

### Phase 2: Configuration Variables (30 minutes)

**File**: `scripts/etc/ad/vars.sh` (new)

```bash
# Active Directory Configuration
AD_DOMAIN="${AD_DOMAIN:-}"
AD_SERVERS="${AD_SERVERS:-}"
AD_BASE_DN="${AD_BASE_DN:-}"  # Auto-detect from domain if empty
AD_USE_SSL="${AD_USE_SSL:-1}"
AD_PORT="${AD_PORT:-636}"  # 636=LDAPS, 389=LDAP, 3269=GC SSL
AD_BIND_DN="${AD_BIND_DN:-}"
AD_BIND_PASSWORD="${AD_BIND_PASSWORD:-}"
AD_USER_SEARCH_BASE="${AD_USER_SEARCH_BASE:-}"
AD_GROUP_SEARCH_BASE="${AD_GROUP_SEARCH_BASE:-}"

# Vault storage
AD_VAULT_SECRET_PATH="${AD_VAULT_SECRET_PATH:-ad/service-accounts/jenkins-admin}"
```

### Phase 3: User Experience Design

**Option A: Environment Variable Selection (RECOMMENDED)**

```bash
# OpenLDAP (default - deploys locally)
./scripts/k3d-manager deploy_jenkins --enable-ldap

# Active Directory (remote - no deployment)
DIRECTORY_SERVICE_PROVIDER=activedirectory \
  ./scripts/k3d-manager deploy_jenkins --enable-ldap
```

**Advantages**:
- ✅ Consistent with existing patterns (`SECRET_BACKEND_PROVIDER`)
- ✅ Works on Mac without requiring local AD
- ✅ `--enable-ldap` becomes "enable directory service integration"
- ✅ No UX changes needed (already implemented in abstraction)
- ✅ Scales to future providers (Azure AD, Okta, etc.)

### Phase 4: Mac Configuration Workflow (1 hour)

**One-time setup** for Mac users:

```bash
# Step 1: Create AD configuration file
cat > ~/.k3d-manager/ad.env <<EOF
AD_DOMAIN=corp.example.com
AD_SERVERS=dc1.corp.example.com,dc2.corp.example.com
AD_BIND_DN=CN=svc-jenkins,OU=ServiceAccounts,DC=corp,DC=example,DC=com
AD_BIND_PASSWORD=SecurePassword123
AD_USER_SEARCH_BASE=OU=Users,DC=corp,DC=example,DC=com
AD_GROUP_SEARCH_BASE=OU=Groups,DC=corp,DC=example,DC=com
EOF

# Step 2: Load config and deploy
source ~/.k3d-manager/ad.env
DIRECTORY_SERVICE_PROVIDER=activedirectory \
  ./scripts/k3d-manager deploy_jenkins --enable-ldap
```

**Validation before deployment**:

```bash
# AD provider init will:
1. Check if AD_DOMAIN is set
2. Attempt ldapsearch to AD_SERVERS
3. Test bind with service account
4. Verify user/group search bases accessible
5. FAIL FAST with helpful message if unreachable

# Example error:
ERROR: [dirservice:activedirectory] Cannot reach AD server dc1.corp.example.com:636
  Are you connected to corporate VPN?
  Test connectivity: ldapsearch -H ldaps://dc1.corp.example.com:636 -x
```

### Phase 5: Testing Strategy (1 hour)

**Mock AD for CI/CD**:
```bash
# Use test OpenLDAP configured with AD-like schema
docker run -d --name mock-ad \
  -p 389:389 -p 636:636 \
  rroemhild/test-openldap
```

**Manual testing with real AD**:
```bash
DIRECTORY_SERVICE_PROVIDER=activedirectory \
  AD_DOMAIN=corp.example.com \
  AD_SERVERS=dc.corp.example.com \
  ./scripts/k3d-manager deploy_jenkins --enable-ldap
```

### Phase 6: Documentation (30 minutes)

Update documentation:
- Add AD section to directory-service-interface.md
- Document configuration workflow for Mac
- Add troubleshooting guide for VPN/connectivity issues

## Technical Details

### Active Directory Schema

**User Object**:
```ldif
dn: CN=John Doe,OU=Users,DC=corp,DC=example,DC=com
objectClass: user
objectClass: person
sAMAccountName: jdoe
cn: John Doe
sn: Doe
mail: john.doe@corp.example.com
memberOf: CN=Developers,OU=Groups,DC=corp,DC=example,DC=com
userPrincipalName: jdoe@corp.example.com
distinguishedName: CN=John Doe,OU=Users,DC=corp,DC=example,DC=com
```

**Group Object**:
```ldif
dn: CN=Developers,OU=Groups,DC=corp,DC=example,DC=com
objectClass: group
cn: Developers
member: CN=John Doe,OU=Users,DC=corp,DC=example,DC=com
```

### Jenkins Active Directory Plugin Configuration

```yaml
securityRealm:
  activeDirectory:
    domains:
      - name: "${AD_DOMAIN}"
        servers: "${AD_SERVERS}"
        bindName: "${AD_BIND_DN}"
        bindPassword: "${AD_BIND_PASSWORD}"
    groupLookupStrategy: RECURSIVE  # Handle nested groups
    removeIrrelevantGroups: false
    requireTLS: true
```

### Nested Group Resolution

Active Directory supports nested groups (groups containing groups). The AD provider will use the `tokenGroups` attribute for efficient resolution:

```bash
# Standard LDAP approach (slow, requires recursive queries)
ldapsearch -b "DC=corp,DC=example,DC=com" \
  "(sAMAccountName=jdoe)" memberOf

# AD-optimized approach (fast, single query)
ldapsearch -b "DC=corp,DC=example,DC=com" \
  "(sAMAccountName=jdoe)" tokenGroups
```

## Implementation Effort

| Task | Estimated Time |
|------|---------------|
| AD provider module | 2-3 hours |
| Configuration variables | 30 minutes |
| Mac workflow documentation | 30 minutes |
| Testing with mock AD | 1 hour |
| Integration testing | 1 hour |
| **Total** | **5-6 hours** |

## Security Considerations

### Service Account Permissions
AD service account needs:
- **Read** on user objects (for authentication)
- **Read** on group objects (for group membership)
- **NO** write permissions required

### TLS Configuration
- Default to LDAPS (port 636) for encrypted communication
- Support certificate validation (avoid `TRUST_ALL_CERTIFICATES` in production)
- Allow certificate bundle specification for corporate CAs

### Credential Storage
- Store AD credentials in Vault (never in git)
- Use Vault's LDAP secrets engine for dynamic credentials (future enhancement)
- Support credential rotation via External Secrets Operator

## Future Enhancements

### Phase 2: Enhanced Features
1. **Kerberos Authentication**: Support Kerberos SSO for AD users
2. **Global Catalog Support**: Query GC for cross-domain lookups (port 3268/3269)
3. **Dynamic Credentials**: Use Vault LDAP secrets engine for auto-rotating credentials
4. **Multi-Domain Support**: Handle multiple AD forests/domains

### Phase 3: Cloud Integrations
1. **Azure AD**: OAuth2/SAML integration for cloud-only environments
2. **Hybrid AD**: Support hybrid on-prem + Azure AD scenarios
3. **AWS Directory Service**: Support AWS managed AD

## Troubleshooting Guide

### Common Issues

**Issue**: Cannot reach AD server
```bash
# Solution: Verify VPN connection
ping dc1.corp.example.com

# Test LDAP connectivity
ldapsearch -H ldaps://dc1.corp.example.com:636 -x \
  -b "DC=corp,DC=example,DC=com" -s base
```

**Issue**: Authentication failed
```bash
# Solution: Verify service account credentials
ldapsearch -H ldaps://dc1.corp.example.com:636 \
  -D "CN=svc-jenkins,OU=ServiceAccounts,DC=corp,DC=example,DC=com" \
  -W -b "DC=corp,DC=example,DC=com" -s base
```

**Issue**: Group membership not resolved
```bash
# Solution: Check user's groups
ldapsearch -H ldaps://dc1.corp.example.com:636 \
  -D "CN=svc-jenkins,..." -W \
  -b "DC=corp,DC=example,DC=com" \
  "(sAMAccountName=username)" memberOf
```

## Related Documentation

- [Directory Service Interface](directory-service-interface.md) - Provider interface specification
- [Configuration-Driven Design](../architecture/configuration-driven-design.md) - Architecture overview
- [CLAUDE.md](../../CLAUDE.md) - Project guidelines
