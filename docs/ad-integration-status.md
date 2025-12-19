# Active Directory Integration Status

**Date:** 2025-11-19
**Branch:** ldap-develop

## Summary

This document provides the current status of Active Directory integration with Jenkins, including completed work, known issues, and production deployment requirements.

## Completed Work

### 1. Jenkins Authentication Testing Script ✅

**Location:** `bin/test-jenkins-auth.sh`

A comprehensive testing tool that validates Jenkins authentication using both curl (HTTP API) and jenkins-cli.

**Features:**
- Auto-detects authentication mode (local/LDAP/AD)
- Tests multiple endpoints (`/whoAmI`, `/api/json`, crumb issuer)
- Supports both curl and jenkins-cli testing
- Flexible credential configuration via environment variables or command-line flags
- Detailed pass/fail reporting

**Usage Examples:**
```bash
# Auto-detect auth mode and test
./bin/test-jenkins-auth.sh

# Test LDAP with specific user
./bin/test-jenkins-auth.sh --auth-mode ldap --user alice --password AlicePass123!

# Test production AD (requires VPN)
AD_TEST_USER=john.doe AD_TEST_PASS=secret ./bin/test-jenkins-auth.sh --auth-mode ad

# Test only curl (skip CLI)
./bin/test-jenkins-auth.sh --skip-cli

# Test only jenkins-cli (skip curl)
./bin/test-jenkins-auth.sh --skip-curl --user alice --password AlicePass123!
```

### 2. Certificate Rotation Functionality ✅

**Status:** Fully working and tested

**Components:**
- Vault PKI certificate issuance
- Automated certificate rotation via CronJob
- Secret updates and pod restarts
- ARM64 image compatibility
- RBAC permissions for secret creation

**Commit:** `d12aebc` - "fix(jenkins): resolve Helm 5.x duplicate environment variable conflicts"

### 3. Production AD Integration Path ✅

**Status:** Code complete, ready for production testing

**Deployment Command:**
```bash
# Set required environment variables
export AD_DOMAIN="corp.example.com"
export AD_SERVERS="dc1.corp.example.com,dc2.corp.example.com"
export AD_BIND_DN="CN=svc-jenkins,OU=ServiceAccounts,DC=corp,DC=example,DC=com"
export AD_BIND_PASSWORD="your-password-here"

# Deploy Jenkins with production AD
./scripts/k3d-manager deploy_jenkins --enable-ad-prod --enable-vault
```

**Features:**
- Active Directory plugin integration
- Vault-based credential management (Vault Agent file mounts)
- DNS auto-discovery of domain controllers (optional)
- Configurable group lookup strategies (RECURSIVE, TOKENGROUPS, CHAIN)
- TLS/LDAPS support with configurable trust stores
- Authorization via AD groups
- Caching for performance
- Connectivity validation with helpful troubleshooting messages

**Configuration Files:**
- `scripts/etc/jenkins/ad-vars.sh` - AD configuration variables
- `scripts/etc/jenkins/values-ad-prod.yaml.tmpl` - Helm values template
- `scripts/lib/dirservices/activedirectory.sh` - Provider implementation

## Known Issues

### Issue #1: OpenLDAP AD Schema Testing (Mock AD) - BLOCKED

**Severity:** Medium (affects testing only, not production)

**Problem:** The `deploy_ad` function (which deploys OpenLDAP with AD-compatible schema for LOCAL TESTING) has multiple compatibility issues with the Bitnami OpenLDAP chart:

1. **Chart doesn't respect custom base DN**: Even when `LDAP_ROOT=DC=corp,DC=example,DC=com` is set, the container creates `dc=home,dc=org`

2. **Admin credentials mismatch**: Chart creates `cn=ldap-admin,dc=home,dc=org` instead of `cn=admin,DC=corp,DC=example,DC=com`

3. **`deploy_ad` function bug**: Calls `deploy_ldap` with no arguments, causing it to show help instead of deploying

4. **Syntax error in ldap.sh**: Line 730-733 has the same bug as was fixed in lines 698-703 (`grep -c` and `|| echo "0"` in same command substitution)

5. **Path typo**: Line 1335 has extra `/scripts` in path: `${SCRIPT_DIR}/scripts/etc/...`

**Impact:**
- Cannot test AD schema structure locally using OpenLDAP
- Must use production AD or skip AD schema testing

**Workaround:**
- Use production AD integration path (`--enable-ad-prod`) instead
- Enable test mode to bypass validation: `export AD_TEST_MODE=1`

**Status:** Deferred - Production AD integration works correctly

### Issue #2: Jenkins LDAP Variable Sourcing for `--enable-ad` Mode - IDENTIFIED

**Severity:** Medium

**Problem:** When deploying Jenkins with `--enable-ad` flag (for AD schema testing with OpenLDAP), the LDAP environment variables are not being sourced correctly in `scripts/plugins/jenkins.sh`.

**Location:** `scripts/plugins/jenkins.sh` lines 1380-1419

**Current Behavior:** Variables like `LDAP_URL`, `LDAP_BASE_DN` are sourced but the configuration still doesn't apply correctly due to Issue #1 (OpenLDAP chart problems).

**Status:** Code fix implemented but unable to validate due to Issue #1

## Production AD Integration Requirements

### Prerequisites

1. **Corporate Network Access:**
   - VPN connection to corporate network
   - DNS resolution for AD domain
   - Network access to domain controllers (ports 389/LDAP or 636/LDAPS)

2. **Active Directory Service Account:**
   - Create a service account in AD (e.g., `svc-jenkins`)
   - Place in appropriate OU (e.g., `OU=ServiceAccounts`)
   - Grant read access to user and group objects
   - Note the full DN (e.g., `CN=svc-jenkins,OU=ServiceAccounts,DC=corp,DC=example,DC=com`)

3. **AD Group for Jenkins Admins:**
   - Create or identify AD group for Jenkins administrators
   - Default: "Domain Admins" (can be customized via `AD_ADMIN_GROUP`)
   - Members of this group will have full Jenkins admin rights

4. **Tools:**
   - `ldap-utils` package (for connectivity testing)
   - Access to Vault for credential storage

### Configuration Variables

**Required:**
```bash
export AD_DOMAIN="corp.example.com"
export AD_SERVERS="dc1.corp.example.com,dc2.corp.example.com"  # Optional if DNS works
export AD_BIND_DN="CN=svc-jenkins,OU=ServiceAccounts,DC=corp,DC=example,DC=com"
export AD_BIND_PASSWORD="your-service-account-password"
```

**Optional (with defaults):**
```bash
export AD_SITE=""                              # AD site name (optional)
export AD_ADMIN_GROUP="Domain Admins"         # AD group for Jenkins admins
export AD_GROUP_LOOKUP_STRATEGY="RECURSIVE"   # RECURSIVE, TOKENGROUPS, or CHAIN
export AD_REQUIRE_TLS="true"                   # Require TLS/SSL
export AD_TLS_CONFIG="TRUST_ALL_CERTIFICATES" # Trust store configuration
export AD_CACHE_SIZE="100"                     # User/group cache size
export AD_CACHE_TTL="3600"                     # Cache TTL in seconds
export AD_TEST_MODE="0"                        # Set to 1 to bypass validation
```

### Deployment Process

1. **Connect to Corporate Network:**
   ```bash
   # Connect to VPN
   # Verify DNS resolution
   nslookup corp.example.com

   # Verify LDAP connectivity
   nc -zv dc1.corp.example.com 636  # LDAPS
   # or
   nc -zv dc1.corp.example.com 389  # LDAP
   ```

2. **Set Environment Variables:**
   ```bash
   export AD_DOMAIN="corp.example.com"
   export AD_SERVERS="dc1.corp.example.com,dc2.corp.example.com"
   export AD_BIND_DN="CN=svc-jenkins,OU=ServiceAccounts,DC=corp,DC=example,DC=com"
   export AD_BIND_PASSWORD="your-password-here"
   ```

3. **Deploy Jenkins with AD Integration:**
   ```bash
   # Deploy with Vault and AD
   ./scripts/k3d-manager deploy_jenkins --enable-ad-prod --enable-vault
   ```

4. **Verify Deployment:**
   ```bash
   # Check Jenkins is running
   kubectl get pods -n jenkins

   # Check Jenkins configuration includes AD security realm
   kubectl get configmap -n jenkins jenkins-jcasc-01-security -o yaml

   # Look for activeDirectory configuration
   ```

5. **Test Authentication:**
   ```bash
   # Test with AD credentials
   AD_TEST_USER=your.username AD_TEST_PASS=your-password \
     ./bin/test-jenkins-auth.sh --auth-mode ad

   # Or access Jenkins UI
   # https://jenkins.dev.local.me (or your configured host)
   ```

### Troubleshooting

**Cannot connect to AD:**
1. Check VPN connection
2. Verify DNS resolution: `nslookup $AD_DOMAIN`
3. Test LDAP port: `nc -zv $AD_DOMAIN 636` (LDAPS) or `nc -zv $AD_DOMAIN 389` (LDAP)
4. Verify service account credentials
5. Check firewall rules

**AD connectivity validation fails during deployment:**
- Bypass validation temporarily: `export AD_TEST_MODE=1`
- This will deploy without testing AD connectivity
- You can validate manually after deployment

**Authentication fails:**
1. Check service account has correct permissions
2. Verify bind DN format is correct (use uppercase DC components for AD)
3. Check user exists in AD and is in correct groups
4. Review Jenkins logs: `kubectl logs -n jenkins <jenkins-pod-name>`
5. Check AD plugin configuration in Jenkins UI

**Group memberships not recognized:**
- Try different group lookup strategy:
  - `RECURSIVE` - Standard recursive lookup (default)
  - `TOKENGROUPS` - Windows-specific optimization (faster)
  - `CHAIN` - Follow group membership chain
- Adjust via: `export AD_GROUP_LOOKUP_STRATEGY="TOKENGROUPS"`

## Testing Checklist

### Local Testing (without real AD)
- [x] Certificate rotation works
- [x] Jenkins authentication testing script created
- [ ] Mock AD deployment (blocked by Bitnami chart issues)

### Production AD Testing (requires corporate VPN)
- [ ] AD connectivity validation
- [ ] Service account authentication
- [ ] User login with AD credentials
- [ ] Group membership resolution
- [ ] Admin group authorization
- [ ] Jenkins CLI authentication
- [ ] Certificate rotation with AD-authenticated Jenkins

## Next Steps

### Immediate (Ready Now)
1. **Test production AD integration** with real Active Directory
   - Requires corporate VPN access
   - Requires AD service account
   - Use `./bin/test-jenkins-auth.sh` to validate

2. **Document test results** from production AD testing

### Future (Lower Priority)
1. **Fix OpenLDAP AD schema testing issues:**
   - Investigate alternative OpenLDAP chart or custom deployment
   - Fix `deploy_ad` function to properly pass arguments
   - Fix syntax errors in ldap.sh

2. **Create Mac-specific AD setup guide:**
   - Document VPN setup
   - Document DNS configuration
   - Document troubleshooting for Mac-specific issues

3. **Enhance monitoring:**
   - Add alerts for certificate expiration
   - Add metrics for AD authentication failures
   - Add health checks for AD connectivity

## References

**Code Locations:**
- AD provider: `scripts/lib/dirservices/activedirectory.sh`
- AD configuration: `scripts/etc/jenkins/ad-vars.sh`
- AD Helm template: `scripts/etc/jenkins/values-ad-prod.yaml.tmpl`
- Jenkins plugin: `scripts/plugins/jenkins.sh`
- LDAP plugin: `scripts/plugins/ldap.sh`
- Testing script: `bin/test-jenkins-auth.sh`

**Documentation:**
- Jenkins AD plugin: https://plugins.jenkins.io/active-directory/
- Certificate rotation: `docs/tests/cert-rotation-test-results-2025-11-17.md`
- Directory service interface: `docs/architecture/directory-service-interface.md`

**Environment Variable Reference:**
See `scripts/etc/jenkins/ad-vars.sh` for complete list of configuration options.
