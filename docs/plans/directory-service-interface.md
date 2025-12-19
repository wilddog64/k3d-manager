# Directory Service Interface Design

## Overview

Design a pluggable interface for directory services to support OpenLDAP, Active Directory, Azure AD, and other authentication backends in a unified way.

**Date**: 2025-11-04
**Status**: Design Proposal
**Related**: secret-backend-interface.md, jenkins-authentication-analysis.md

---

## Current State Analysis

### Existing Implementations

**OpenLDAP** (ldap-develop branch - current):
- Location: `scripts/plugins/ldap.sh`
- JCasC Security Realm: `ldap` plugin
- Credentials: Vault secret at `secret/ldap/service-accounts/jenkins-admin`
- Configuration via environment variables:
  ```yaml
  - name: LDAP_URL
    value: "ldap://openldap.directory.svc.cluster.local:389"
  - name: LDAP_BASE_DN / LDAP_GROUP_SEARCH_BASE / LDAP_USER_SEARCH_BASE
    valueFrom: secretKeyRef (jenkins-ldap-config)
  ```
- JCasC snippet (scripts/etc/jenkins/values.yaml:142-156):
  ```yaml
  securityRealm:
    ldap:
      configurations:
        - server: "${LDAP_URL}"
          rootDN: "${LDAP_BASE_DN}"
          groupSearchBase: "${LDAP_GROUP_SEARCH_BASE}"
          userSearchBase: "${LDAP_USER_SEARCH_BASE}"
          managerDN: "${LDAP_BIND_DN}"
          managerPasswordSecret: "${LDAP_BIND_PASSWORD}"
  ```

**Active Directory** (baseline branch - has defects):
- Location: AD integration merged at commit `e1c5645`
- JCasC Security Realm: `activeDirectory` plugin
- Credentials: Vault secret at `secret/jenkins/ad-ldap`
- Manual sync script: `bin/sync-lastpass-ad.sh` (from LastPass)
- Configuration via Vault Agent file references:
  ```yaml
  securityRealm:
    activeDirectory:
      bindPassword: "${file:/vault/secrets/ad-ldap-bind-password}"
      domains:
        - bindName: "${file:/vault/secrets/ad-ldap-bind-username}"
          bindPassword: "${file:/vault/secrets/ad-ldap-bind-password}"
          name: "pacific.costcotravel.com"
          tlsConfiguration: "TRUST_ALL_CERTIFICATES"
      groupLookupStrategy: "TOKENGROUPS"
      internalUsersDatabase:
        jenkinsInternalUser: "${JENKINS_ADMIN_USER}"
      requireTLS: true
  ```

### Key Architectural Differences

| Aspect | OpenLDAP | Active Directory |
|--------|----------|------------------|
| **JCasC Plugin** | `ldap` | `activeDirectory` |
| **Credential Injection** | Environment variables | Vault Agent file mounts |
| **Secret Path** | `secret/ldap/service-accounts/jenkins-admin` | `secret/jenkins/ad-ldap` |
| **Domain Spec** | Generic LDAP URL | Windows domain (pacific.costcotravel.com) |
| **TLS** | Optional | Required (`requireTLS: true`) |
| **Group Lookup** | Standard LDAP search | TOKENGROUPS (AD-specific) |
| **Fallback Admin** | None (implicit) | Explicit `internalUsersDatabase` |
| **Deployment** | OpenLDAP in cluster | External AD server |

---

## Design Goals

1. **Pluggable Directory Services**: Support LDAP, AD, Azure AD, Okta with minimal code changes
2. **Unified Configuration**: Single interface for all directory service operations
3. **Secret Backend Integration**: Work with Vault, Azure Key Vault, AWS, GCP secrets
4. **JCasC Template Generation**: Dynamically generate Jenkins security realm config
5. **Backward Compatibility**: Existing deployments continue to work

---

## Critical Issues to Address

### Issue #1: JCasC Authorization Strategy Conflict

**Problem**: Current ldap-develop uses nested `entries:` format for projectMatrix, but this conflicts with directory groups and may confuse built-in groups.

**Current (ldap-develop)** - scripts/etc/jenkins/values.yaml:157-164:
```yaml
authorizationStrategy:
  projectMatrix:
    entries:
      - group:
          name: "jenkins-admins"
          permissions:
            - "Overall/Read"
            - "Overall/Administer"
```

**Baseline (AD implementation)** - uses flat permissions format:
```yaml
authorizationStrategy:
  projectMatrix:
    permissions:
      - "Overall/Read:${JENKINS_ADMIN_USER}"
      - "Overall/Administer:${JENKINS_ADMIN_USER}"
      - "Overall/Read:it devops"
      - "Overall/Administer:it devops"
      - "Overall/Read:authenticated"
      - "Overall/Administer:group:it devops"
      - "Overall/Read:group:it devops"
```

**Why Baseline Format is Better**:
- Uses `permission:principal` syntax (standard matrix-auth format)
- Explicit `group:` prefix for LDAP/AD groups vs user principals
- `authenticated` pseudo-group for all logged-in users
- Allows mixing users and groups in single config
- Less ambiguous parsing by Jenkins

**Recommendation**:
- Standardize on flat `permissions:` format
- Use `user:username` and `group:groupname` prefixes explicitly
- Generate dynamically based on directory service type
- Allow configuration via `JENKINS_AUTHZ_PERMISSIONS` environment variable

### Issue #2: Login Smoke Testing

**Problem**: After Jenkins deployment, no automated verification that directory authentication works.

**Required Smoke Tests**:
1. **Local Admin Login** (Vault-only mode):
   - Retrieve admin password from Vault/ESO
   - Attempt login via Jenkins API
   - Verify admin has Overall/Administer permission

2. **LDAP User Login** (--enable-ldap mode):
   - Use test LDAP user credentials
   - Attempt login via Jenkins API
   - Verify user belongs to correct groups
   - Verify group permissions applied correctly

3. **AD User Login** (--enable-ad mode):
   - Use test AD user credentials
   - Attempt login via Jenkins API
   - Verify AD group membership resolved
   - Verify TOKENGROUPS lookup working

4. **Azure AD SSO** (--enable-azure-ad mode):
   - Verify SAML metadata accessible
   - Test SSO redirect flow (requires browser automation)

**Implementation**:
```bash
function dirservice_smoke_test_login() {
   local jenkins_url="$1"
   local test_user="$2"
   local test_password="$3"

   # Attempt authentication via Jenkins CLI
   local crumb
   crumb=$(curl -s -u "$test_user:$test_password" \
      "$jenkins_url/crumbIssuer/api/json" | jq -r '.crumb')

   if [[ -z "$crumb" ]]; then
      _err "[smoke-test] Failed to authenticate user: $test_user"
      return 1
   fi

   # Verify whoAmI
   local whoami
   whoami=$(curl -s -u "$test_user:$test_password" \
      -H "Jenkins-Crumb: $crumb" \
      "$jenkins_url/me/api/json" | jq -r '.id')

   if [[ "$whoami" != "$test_user" ]]; then
      _err "[smoke-test] User mismatch: expected $test_user, got $whoami"
      return 1
   fi

   _info "[smoke-test] ✓ User $test_user authenticated successfully"
   return 0
}
```

---

## Proposed Interface

### Core Abstraction Layer

Create `scripts/lib/directory_service.sh` with provider interface:

```bash
#!/usr/bin/env bash
# scripts/lib/directory_service.sh
# Directory service abstraction for Jenkins authentication

# Supported directory services: ldap, ad, azure-ad, okta
DIRECTORY_SERVICE="${DIRECTORY_SERVICE:-ldap}"

# Provider Interface - all directory service providers must implement:
#
# 1. dirservice_init()
#    - Deploy directory service (if self-hosted like OpenLDAP)
#    - Returns: 0 on success
#
# 2. dirservice_create_credentials(secret_backend, secret_path, ...)
#    - Create service account credentials in secret backend
#    - Args: secret backend type, path, provider-specific params
#    - Returns: 0 on success
#
# 3. dirservice_generate_jcasc(namespace, secret_name, output_file)
#    - Generate JCasC securityRealm configuration
#    - Args: namespace, K8s secret name, output file path
#    - Returns: 0 on success, writes YAML to output_file
#
# 4. dirservice_generate_env_vars(secret_name, output_file)
#    - Generate environment variable configuration for Helm values
#    - Args: K8s secret name, output file path
#    - Returns: 0 on success, writes YAML snippet to output_file
#
# 5. dirservice_validate_config()
#    - Validate directory service configuration (reachability, credentials)
#    - Returns: 0 if valid, 1 if invalid
#
# 6. dirservice_get_groups(username)
#    - Query user's group memberships (for testing/validation)
#    - Args: username
#    - Returns: 0 on success, prints groups to stdout
#
# 7. dirservice_generate_authz(output_file, permissions_env)
#    - Generate JCasC authorizationStrategy configuration
#    - Args: output file path, permissions environment variable name
#    - Returns: 0 on success, writes YAML to output_file
#    - Uses flat permissions: format (permission:principal)
#
# 8. dirservice_smoke_test_login(jenkins_url, test_user, test_password)
#    - Smoke test Jenkins login with directory credentials
#    - Args: Jenkins URL, test username, test password
#    - Returns: 0 if login successful, 1 otherwise

function _get_directory_service() {
   echo "${DIRECTORY_SERVICE}"
}

function _load_dirservice_provider() {
   local dirservice="${1:-$DIRECTORY_SERVICE}"
   local provider_plugin="$PLUGINS_DIR/dirservice-${dirservice}.sh"

   if [[ ! -f "$provider_plugin" ]]; then
      _err "[directory-service] Provider plugin not found: $provider_plugin"
      return 1
   fi

   # Source the provider plugin
   # shellcheck disable=SC1090
   source "$provider_plugin"

   # Verify provider implements required interface
   local -a required_functions=(
      "${dirservice}_dirservice_init"
      "${dirservice}_dirservice_create_credentials"
      "${dirservice}_dirservice_generate_jcasc"
      "${dirservice}_dirservice_generate_env_vars"
      "${dirservice}_dirservice_validate_config"
      "${dirservice}_dirservice_get_groups"
      "${dirservice}_dirservice_generate_authz"
      "${dirservice}_dirservice_smoke_test_login"
   )

   local func
   for func in "${required_functions[@]}"; do
      if ! declare -F "$func" >/dev/null 2>&1; then
         _err "[directory-service] Provider '$dirservice' missing required function: $func"
         return 1
      fi
   done
}

# Generic wrapper functions that delegate to active provider
function dirservice_init() {
   local dirservice="$(_get_directory_service)"
   _load_dirservice_provider "$dirservice" || return 1
   "${dirservice}_dirservice_init" "$@"
}

function dirservice_create_credentials() {
   local dirservice="$(_get_directory_service)"
   _load_dirservice_provider "$dirservice" || return 1
   "${dirservice}_dirservice_create_credentials" "$@"
}

function dirservice_generate_jcasc() {
   local dirservice="$(_get_directory_service)"
   _load_dirservice_provider "$dirservice" || return 1
   "${dirservice}_dirservice_generate_jcasc" "$@"
}

function dirservice_generate_env_vars() {
   local dirservice="$(_get_directory_service)"
   _load_dirservice_provider "$dirservice" || return 1
   "${dirservice}_dirservice_generate_env_vars" "$@"
}

function dirservice_validate_config() {
   local dirservice="$(_get_directory_service)"
   _load_dirservice_provider "$dirservice" || return 1
   "${dirservice}_dirservice_validate_config" "$@"
}

function dirservice_get_groups() {
   local dirservice="$(_get_directory_service)"
   _load_dirservice_provider "$dirservice" || return 1
   "${dirservice}_dirservice_get_groups" "$@"
}

function dirservice_generate_authz() {
   local dirservice="$(_get_directory_service)"
   _load_dirservice_provider "$dirservice" || return 1
   "${dirservice}_dirservice_generate_authz" "$@"
}

function dirservice_smoke_test_login() {
   local dirservice="$(_get_directory_service)"
   _load_dirservice_provider "$dirservice" || return 1
   "${dirservice}_dirservice_smoke_test_login" "$@"
}
```

---

## Provider Implementations

### OpenLDAP Provider (scripts/plugins/dirservice-ldap.sh)

Refactor existing ldap.sh logic:

```bash
#!/usr/bin/env bash
# scripts/plugins/dirservice-ldap.sh
# OpenLDAP directory service provider

function ldap_dirservice_init() {
   # Deploy OpenLDAP to cluster
   deploy_ldap "$@"
}

function ldap_dirservice_create_credentials() {
   local secret_backend="$1"
   local secret_path="$2"
   local username="${3:-jenkins-admin}"
   local password="${4:-}"

   # Generate password if not provided
   if [[ -z "$password" ]]; then
      password=$(openssl rand -base64 24)
   fi

   # Store in secret backend using backend abstraction
   backend_create_secret "$secret_path" \
      "username=$username" \
      "password=$password"
}

function ldap_dirservice_generate_jcasc() {
   local namespace="$1"
   local secret_name="$2"
   local output_file="$3"

   local ldap_url="${LDAP_URL:-ldap://openldap.directory.svc.cluster.local:389}"
   local base_dn="${LDAP_BASE_DN:-dc=example,dc=com}"

   cat > "$output_file" <<EOF
securityRealm:
  ldap:
    configurations:
      - server: "${ldap_url}"
        rootDN: "${base_dn}"
        groupSearchBase: "ou=groups"
        userSearchBase: "ou=service"
        managerDN: "\${LDAP_BIND_DN}"
        managerPasswordSecret: "\${LDAP_BIND_PASSWORD}"
        inhibitInferRootDN: false
        displayNameAttributeName: "cn"
        mailAddressAttributeName: "mail"
    disableMailAddressResolver: false
EOF
}

function ldap_dirservice_generate_env_vars() {
   local secret_name="$1"
   local output_file="$2"

   local ldap_url="${LDAP_URL:-ldap://openldap.directory.svc.cluster.local:389}"

   cat > "$output_file" <<EOF
- name: LDAP_URL
  value: "${ldap_url}"
- name: LDAP_GROUP_SEARCH_BASE
  value: "ou=groups"
- name: LDAP_USER_SEARCH_BASE
  value: "ou=service"
- name: LDAP_BASE_DN
  valueFrom:
    secretKeyRef:
      name: ${secret_name}
      key: LDAP_BASE_DN
- name: LDAP_BIND_DN
  valueFrom:
    secretKeyRef:
      name: ${secret_name}
      key: LDAP_BIND_DN
- name: LDAP_BIND_PASSWORD
  valueFrom:
    secretKeyRef:
      name: ${secret_name}
      key: LDAP_BIND_PASSWORD
EOF
}

function ldap_dirservice_validate_config() {
   # Test LDAP connectivity
   local ldap_url="${LDAP_URL:-ldap://openldap.directory.svc.cluster.local:389}"

   if command -v ldapsearch >/dev/null 2>&1; then
      ldapsearch -x -H "$ldap_url" -b "dc=example,dc=com" -s base >/dev/null 2>&1
      return $?
   else
      _warn "[ldap] ldapsearch not available, skipping validation"
      return 0
   fi
}

function ldap_dirservice_get_groups() {
   local username="$1"
   local ldap_url="${LDAP_URL:-ldap://openldap.directory.svc.cluster.local:389}"
   local base_dn="${LDAP_BASE_DN:-dc=example,dc=com}"

   if command -v ldapsearch >/dev/null 2>&1; then
      ldapsearch -x -H "$ldap_url" -b "$base_dn" \
         "(memberUid=$username)" cn | grep "^cn:" | cut -d' ' -f2
   else
      _err "[ldap] ldapsearch command not found"
      return 1
   fi
}
```

### Active Directory Provider (NEW - scripts/plugins/dirservice-ad.sh)

Clean implementation based on baseline (fixing known defects):

```bash
#!/usr/bin/env bash
# scripts/plugins/dirservice-ad.sh
# Active Directory directory service provider

function ad_dirservice_init() {
   # AD is external, no deployment needed
   # Validate connectivity instead
   ad_dirservice_validate_config
}

function ad_dirservice_create_credentials() {
   local secret_backend="$1"
   local secret_path="$2"
   local bind_dn="${3:-}"  # Full AD bind DN
   local password="${4:-}"

   if [[ -z "$bind_dn" ]]; then
      _err "[ad] AD bind DN required (e.g., CN=svcJenkins,OU=Service Accounts,DC=example,DC=com)"
      return 1
   fi

   if [[ -z "$password" ]]; then
      _err "[ad] AD bind password required"
      return 1
   fi

   # Store in secret backend
   backend_create_secret "$secret_path" \
      "username=$bind_dn" \
      "password=$password"
}

function ad_dirservice_generate_jcasc() {
   local namespace="$1"
   local secret_name="$2"
   local output_file="$3"

   local ad_domain="${AD_DOMAIN:-example.com}"
   local admin_user="${JENKINS_ADMIN_USER:-admin}"

   # AD uses Vault Agent file mounts instead of env vars
   cat > "$output_file" <<EOF
securityRealm:
  activeDirectory:
    bindPassword: "\${file:/vault/secrets/ad-ldap-bind-password}"
    cache:
      size: 50
      ttl: 3600
    customDomain: true
    domains:
      - bindName: "\${file:/vault/secrets/ad-ldap-bind-username}"
        bindPassword: "\${file:/vault/secrets/ad-ldap-bind-password}"
        name: "${ad_domain}"
        tlsConfiguration: "TRUST_ALL_CERTIFICATES"
    groupLookupStrategy: "TOKENGROUPS"
    internalUsersDatabase:
      jenkinsInternalUser: "${admin_user}"
    removeIrrelevantGroups: false
    requireTLS: true
EOF
}

function ad_dirservice_generate_env_vars() {
   local secret_name="$1"
   local output_file="$2"

   # AD doesn't use environment variables
   # Credentials mounted as files via Vault Agent
   # Return empty YAML snippet
   cat > "$output_file" <<EOF
# Active Directory uses Vault Agent file mounts
# No environment variables required
EOF
}

function ad_dirservice_validate_config() {
   local ad_domain="${AD_DOMAIN:-}"
   local ad_server="${AD_SERVER:-}"

   if [[ -z "$ad_domain" ]]; then
      _err "[ad] AD_DOMAIN not set"
      return 1
   fi

   if [[ -z "$ad_server" ]]; then
      # Try to discover AD server via DNS
      if command -v nslookup >/dev/null 2>&1; then
         ad_server=$(nslookup -type=SRV _ldap._tcp.dc._msdcs."$ad_domain" 2>/dev/null | \
            grep "service =" | head -1 | awk '{print $NF}' | sed 's/\.$//')
      fi
   fi

   if [[ -n "$ad_server" ]]; then
      _info "[ad] Testing connectivity to AD server: $ad_server"
      if command -v ldapsearch >/dev/null 2>&1; then
         ldapsearch -x -H "ldap://$ad_server" -b "dc=${ad_domain//./,dc=}" -s base >/dev/null 2>&1
         return $?
      fi
   fi

   _warn "[ad] Could not validate AD connectivity (ldapsearch not available)"
   return 0
}

function ad_dirservice_get_groups() {
   local username="$1"
   local ad_domain="${AD_DOMAIN:-example.com}"
   local ad_server="${AD_SERVER:-}"

   # AD group lookup requires authenticated bind
   # This is a placeholder - would need bind credentials
   _err "[ad] Group lookup not implemented (requires authenticated bind)"
   return 1
}
```

### Azure AD Provider (NEW - scripts/plugins/dirservice-azure-ad.sh)

```bash
#!/usr/bin/env bash
# scripts/plugins/dirservice-azure-ad.sh
# Azure Active Directory directory service provider

function azure-ad_dirservice_init() {
   # Azure AD is cloud service, no deployment
   # Verify Azure AD app registration exists
   _info "[azure-ad] Verify Azure AD app registration for Jenkins"
}

function azure-ad_dirservice_create_credentials() {
   local secret_backend="$1"
   local secret_path="$2"
   local client_id="${3:-}"
   local client_secret="${4:-}"
   local tenant_id="${5:-}"

   if [[ -z "$client_id" ]] || [[ -z "$client_secret" ]] || [[ -z "$tenant_id" ]]; then
      _err "[azure-ad] Client ID, secret, and tenant ID required"
      return 1
   fi

   backend_create_secret "$secret_path" \
      "clientId=$client_id" \
      "clientSecret=$client_secret" \
      "tenantId=$tenant_id"
}

function azure-ad_dirservice_generate_jcasc() {
   local namespace="$1"
   local secret_name="$2"
   local output_file="$3"

   local tenant_id="${AZURE_TENANT_ID:-}"

   # Azure AD uses SAML or OIDC plugin
   cat > "$output_file" <<EOF
securityRealm:
  saml:
    idpMetadataConfiguration:
      url: "https://login.microsoftonline.com/${tenant_id}/federationmetadata/2007-06/federationmetadata.xml"
    displayNameAttributeName: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name"
    groupsAttributeName: "http://schemas.microsoft.com/ws/2008/06/identity/claims/groups"
    maximumAuthenticationLifetime: 86400
    usernameAttributeName: "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name"
EOF
}

# ... other interface functions ...
```

---

## Jenkins Integration Refactoring

Update `scripts/plugins/jenkins.sh` to use directory service abstraction:

```bash
# After argument parsing (~line 850)
local enable_ldap=0
local enable_ad=0
local directory_service="${DIRECTORY_SERVICE:-ldap}"

# Validate directory service
case "$directory_service" in
   ldap|ad|azure-ad|okta) ;;
   *)
      _err "[jenkins] Unsupported DIRECTORY_SERVICE: $directory_service"
      ;;
esac

# Load directory service library
source "$SCRIPT_DIR/lib/directory_service.sh"

# Initialize directory service
if (( enable_ldap || enable_ad )); then
   dirservice_init || _err "[jenkins] Failed to initialize directory service: $directory_service"
fi

# Create directory service credentials
dirservice_create_credentials "vault" "jenkins/auth/${directory_service}"

# Generate JCasC security realm
local jcasc_security_file
jcasc_security_file=$(mktemp -t jenkins-jcasc-security.XXXXXX.yaml)
dirservice_generate_jcasc "$jenkins_namespace" "jenkins-auth" "$jcasc_security_file"

# Generate environment variables (if needed)
local env_vars_file
env_vars_file=$(mktemp -t jenkins-env-vars.XXXXXX.yaml)
dirservice_generate_env_vars "jenkins-auth" "$env_vars_file"

# Merge generated configs into Helm values
# ...
```

---

## Configuration

### Environment Variables

```bash
# Select directory service provider
export DIRECTORY_SERVICE=ldap|ad|azure-ad|okta

# Provider-specific config

# OpenLDAP
export LDAP_URL=ldap://openldap.directory.svc.cluster.local:389
export LDAP_BASE_DN=dc=example,dc=com

# Active Directory
export AD_DOMAIN=corp.example.com
export AD_SERVER=ad.corp.example.com
export AD_BIND_DN="CN=svcJenkins,OU=Service Accounts,DC=corp,DC=example,DC=com"

# Azure AD
export AZURE_TENANT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export AZURE_AD_CLIENT_ID=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy

# Okta
export OKTA_DOMAIN=mycompany.okta.com
export OKTA_CLIENT_ID=zzzzzzzzzzzzzzzzzzzz
```

### Usage Examples

```bash
# OpenLDAP (default)
export DIRECTORY_SERVICE=ldap
./scripts/k3d-manager deploy_jenkins --enable-ldap --enable-vault

# Active Directory
export DIRECTORY_SERVICE=ad
export AD_DOMAIN=corp.example.com
export AD_BIND_DN="CN=svcJenkins,OU=Service Accounts,DC=corp,DC=example,DC=com"
./scripts/k3d-manager deploy_jenkins --enable-ad --enable-vault

# Azure AD
export DIRECTORY_SERVICE=azure-ad
export AZURE_TENANT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
./scripts/k3d-manager deploy_jenkins --enable-azure-ad --enable-vault
```

---

## Migration Plan

### Phase 1: Extract Current LDAP to Provider (Week 1)
1. Create `scripts/lib/directory_service.sh` with interface
2. Create `scripts/plugins/dirservice-ldap.sh` from existing ldap.sh
3. Refactor jenkins.sh to use dirservice abstraction for LDAP
4. Test LDAP deployment with new interface
5. Update tests

### Phase 2: Implement AD Provider (Week 2)
1. Create `scripts/plugins/dirservice-ad.sh`
2. Cherry-pick working AD code from baseline branch (fix defects)
3. Test AD deployment
4. Add AD-specific tests
5. Document known limitations

### Phase 3: Add Azure AD/Okta (Week 3-4)
1. Create `scripts/plugins/dirservice-azure-ad.sh`
2. Create `scripts/plugins/dirservice-okta.sh`
3. Test cloud directory services
4. Update documentation

### Phase 4: Integration with Secret Backend (Week 5)
1. Ensure directory service works with all secret backends (Vault, Azure, AWS, GCP)
2. Test matrix: (LDAP/AD/Azure AD) × (Vault/Azure KV/AWS/GCP)
3. Comprehensive documentation

---

## Open Questions

1. **Vault Agent vs Environment Variables**: Should we standardize on one approach?
   - AD baseline uses Vault Agent file mounts
   - LDAP uses environment variables
   - Recommendation: Support both, provider chooses best method

2. **Group Sync**: Should we support automatic group creation in Jenkins from directory?
   - AD/LDAP groups → Jenkins roles mapping
   - Requires additional JCasC configuration

3. **Multi-Domain Support**: How to handle multiple AD domains or LDAP servers?
   - Single provider instance per domain?
   - Provider supports multiple domains natively?

4. **Credential Rotation**: How to handle AD/LDAP service account password rotation?
   - Manual via helper scripts (current baseline approach)?
   - Automatic via Vault LDAP secrets engine?

---

## Known Defects from Baseline (to fix in Phase 2)

Based on examination of baseline branch AD implementation:

1. **Hardcoded Domain**: `pacific.costcotravel.com` hardcoded in values.yaml
2. **Manual Credential Sync**: `bin/sync-lastpass-ad.sh` requires LastPass
3. **No Validation**: Missing AD connectivity checks before deployment
4. **TLS Trust All**: `TRUST_ALL_CERTIFICATES` is insecure for production
5. **Missing Error Handling**: AD failures don't provide clear error messages

---

## Related Files

- `scripts/lib/directory_service.sh` - NEW: Abstraction layer
- `scripts/plugins/dirservice-ldap.sh` - NEW: OpenLDAP provider
- `scripts/plugins/dirservice-ad.sh` - NEW: Active Directory provider
- `scripts/plugins/dirservice-azure-ad.sh` - NEW: Azure AD provider
- `scripts/plugins/jenkins.sh` - UPDATE: Use dirservice abstraction
- `scripts/etc/jenkins/values.yaml` - UPDATE: Template-based security realm generation
- baseline branch commit `e1c5645` - Reference AD implementation

---

## Additional Enhancements

### UX Enhancement: Show Help When No Arguments Provided

**Issue**: Currently, `deploy_jenkins` without arguments deploys a minimal Jenkins instance. This may be confusing for users expecting to see help.

**Current Behavior**:
```bash
./scripts/k3d-manager deploy_jenkins  # Deploys minimal Jenkins (no LDAP, no Vault)
./scripts/k3d-manager deploy_jenkins -h  # Shows help
```

**Proposed Behavior**:
```bash
./scripts/k3d-manager deploy_jenkins  # Shows help message
./scripts/k3d-manager deploy_jenkins --minimal  # Deploys minimal Jenkins
```

**Implementation**:
1. Detect when no arguments provided (argc == 0)
2. Display help message and exit
3. Require explicit flag for minimal deployment (e.g., `--minimal` or `--basic`)

**File to Update**:
- `scripts/plugins/jenkins.sh:deploy_jenkins()` - Line 722

**Priority**: Low - Can be implemented alongside directory service interface work
