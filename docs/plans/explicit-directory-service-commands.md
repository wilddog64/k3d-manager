# Explicit Directory Service Commands - Design

## Problem Statement

Currently, deploying LDAP with a custom LDIF file requires manual coordination of multiple environment variables:
- `LDAP_LDIF_FILE` (which LDIF to load)
- `LDAP_BASE_DN` (base DN configuration)
- `LDAP_BINDDN` (bind DN configuration)

This is error-prone and confusing. Users can easily create configuration mismatches where the LDIF content uses one base DN but the deployment configuration uses another.

## Solution: Explicit Commands and Flags

### Design Principles

1. **Explicit is better than implicit** - User should clearly state their intent
2. **Commands match intent** - `deploy_ldap` for LDAP, `deploy_ad` for AD
3. **Mutual exclusivity** - Jenkins can't use both LDAP and AD simultaneously
4. **Backward compatibility** - Existing `deploy_ldap` behavior unchanged
5. **DRY principle** - Both commands share the same underlying code via directory service abstraction

### Command Structure

#### New Command: `deploy_ad`

Deploys OpenLDAP configured with Active Directory-compatible schema for testing.

```bash
./scripts/k3d-manager deploy_ad [namespace] [release]

Options:
  --namespace <ns>       Namespace for AD directory (default: directory)
  --release <name>       Helm release name (default: openldap)
  --test-mode            Use OpenLDAP with AD schema (default: true for now)
  -h, --help             Show help message

Examples:
  # Deploy OpenLDAP with AD-compatible schema
  ./scripts/k3d-manager deploy_ad

  # Deploy to custom namespace
  ./scripts/k3d-manager deploy_ad --namespace ad-test
```

**What it does:**
1. Sets `DIRECTORY_SERVICE_PROVIDER=activedirectory`
2. Sets `DIRECTORY_SERVICE_TEST_MODE=true`
3. Auto-configures:
   - `LDAP_LDIF_FILE="${SCRIPT_DIR}/scripts/etc/ldap/bootstrap-ad-schema.ldif"`
   - `LDAP_BASE_DN="DC=corp,DC=example,DC=com"`
   - `LDAP_BINDDN="cn=admin,DC=corp,DC=example,DC=com"`
   - `LDAP_DOMAIN="corp.example.com"`
4. Calls `deploy_ldap` with provider-specific configuration

#### Existing Command: `deploy_ldap`

Remains unchanged for backward compatibility. Deploys OpenLDAP with default schema.

```bash
./scripts/k3d-manager deploy_ldap [namespace] [release]
```

**Behavior:**
- If `DIRECTORY_SERVICE_PROVIDER` is set, auto-configures based on provider
- Otherwise, uses default OpenLDAP configuration (dc=home,dc=org)

#### Updated Command: `deploy_jenkins`

Add `--enable-ad` flag, make `--enable-ldap` and `--enable-ad` mutually exclusive.

```bash
./scripts/k3d-manager deploy_jenkins [options]

Options:
  --enable-ldap          Deploy with OpenLDAP integration
  --enable-ad            Deploy with Active Directory integration
  --enable-vault         Deploy Vault integration
  --disable-ldap         Skip LDAP deployment
  --disable-vault        Skip Vault deployment
  --namespace <ns>       Jenkins namespace (default: jenkins)
  --vault-namespace <ns> Vault namespace (default: vault)
  --vault-release <name> Vault release name (default: vault)
  -h, --help             Show help message

Examples:
  # Jenkins with OpenLDAP authentication
  ./scripts/k3d-manager deploy_ldap
  ./scripts/k3d-manager deploy_jenkins --enable-ldap --enable-vault

  # Jenkins with Active Directory authentication
  ./scripts/k3d-manager deploy_ad
  ./scripts/k3d-manager deploy_jenkins --enable-ad --enable-vault

  # ERROR: Cannot specify both
  ./scripts/k3d-manager deploy_jenkins --enable-ldap --enable-ad
  # Output: [ERROR] [jenkins] Cannot enable both --enable-ldap and --enable-ad
```

**Flag Validation:**
```bash
if [[ "$enable_ldap" == "1" && "$enable_ad" == "1" ]]; then
   _err "[jenkins] Cannot enable both --enable-ldap and --enable-ad"
fi
```

### Implementation Details

#### 1. Create `deploy_ad` function in `scripts/plugins/ldap.sh`

```bash
function deploy_ad() {
   local restore_trace=0
   if [[ "$-" =~ x ]]; then
      set +x
      restore_trace=1
   fi

   cat <<'EOF'
Usage: deploy_ad [options]

Deploy OpenLDAP with Active Directory-compatible schema for testing.

Options:
  --namespace <ns>   Namespace (default: directory)
  --release <name>   Release name (default: openldap)
  --test-mode        Use OpenLDAP with AD schema (default: true)
  -h, --help         Show this help

Examples:
  deploy_ad
  deploy_ad --namespace ad-test
EOF

   if (( restore_trace )); then set -x; fi

   # Set directory service provider to AD with test mode
   export DIRECTORY_SERVICE_PROVIDER=activedirectory
   export DIRECTORY_SERVICE_TEST_MODE=true

   # Auto-configure AD-compatible settings
   export LDAP_LDIF_FILE="${SCRIPT_DIR}/scripts/etc/ldap/bootstrap-ad-schema.ldif"
   export LDAP_BASE_DN="DC=corp,DC=example,DC=com"
   export LDAP_BINDDN="cn=admin,DC=corp,DC=example,DC=com"
   export LDAP_DOMAIN="corp.example.com"
   export LDAP_ROOT="DC=corp,DC=example,DC=com"

   _info "[ad] deploying Active Directory-compatible OpenLDAP"
   _info "[ad] using AD schema: ${LDAP_LDIF_FILE}"
   _info "[ad] base DN: ${LDAP_BASE_DN}"

   # Call deploy_ldap with AD configuration
   deploy_ldap "$@"
}
```

#### 2. Update `deploy_jenkins` function argument parsing

Add `--enable-ad` flag handling:

```bash
# In deploy_jenkins argument parsing section
local enable_ldap="${JENKINS_LDAP_ENABLED:-0}"
local enable_ad=0
local enable_vault="${JENKINS_VAULT_ENABLED:-0}"

while [[ $# -gt 0 ]]; do
   case "$1" in
      --enable-ldap)
         enable_ldap=1
         shift
         ;;
      --enable-ad)
         enable_ad=1
         shift
         ;;
      --disable-ldap)
         enable_ldap=0
         shift
         ;;
      # ... rest of argument parsing
   esac
done

# Validation: mutual exclusivity
if [[ "$enable_ldap" == "1" && "$enable_ad" == "1" ]]; then
   _err "[jenkins] Cannot enable both --enable-ldap and --enable-ad"
fi

# Set directory service provider based on flag
if [[ "$enable_ad" == "1" ]]; then
   export DIRECTORY_SERVICE_PROVIDER=activedirectory
   export DIRECTORY_SERVICE_TEST_MODE=true
elif [[ "$enable_ldap" == "1" ]]; then
   export DIRECTORY_SERVICE_PROVIDER=openldap
fi
```

#### 3. Update directory service initialization in `deploy_jenkins`

```bash
# Deploy directory service if enabled
if [[ "$enable_ldap" == "1" ]]; then
   _info "[jenkins] deploying OpenLDAP directory service"
   if ! dirservice_init "$jenkins_namespace" "$jenkins_release" "$vault_ns" "$vault_release"; then
      _err "[jenkins] OpenLDAP directory service deployment failed"
   fi
elif [[ "$enable_ad" == "1" ]]; then
   _info "[jenkins] deploying Active Directory-compatible directory service"
   if ! dirservice_init "$jenkins_namespace" "$jenkins_release" "$vault_ns" "$vault_release"; then
      _err "[jenkins] Active Directory directory service deployment failed"
   fi
fi
```

### Testing Workflow

#### Phase 1: OpenLDAP with AD Schema

```bash
# Step 1: Deploy AD-compatible OpenLDAP
./scripts/k3d-manager deploy_ad

# Step 2: Verify AD schema loaded
kubectl exec -n directory $(kubectl get pods -n directory -l app.kubernetes.io/name=openldap-bitnami -o jsonpath='{.items[0].metadata.name}') -- \
  ldapsearch -x -D "cn=admin,DC=corp,DC=example,DC=com" \
  -w "$(kubectl get secret openldap-admin -n directory -o jsonpath='{.data.LDAP_ADMIN_PASSWORD}' | base64 -d)" \
  -b "DC=corp,DC=example,DC=com" -LLL "(objectClass=*)" dn

# Expected output: DC=corp,DC=example,DC=com structure

# Step 3: Deploy Jenkins with AD integration
./scripts/k3d-manager deploy_jenkins --enable-ad --enable-vault

# Step 4: Test login with AD users
# alice@corp.example.com / AlicePass123!
# bob@corp.example.com / BobPass456!
```

#### Phase 2: Real Active Directory (Future)

```bash
# Step 1: Configure real AD connection
export DIRECTORY_SERVICE_PROVIDER=activedirectory
export DIRECTORY_SERVICE_TEST_MODE=false  # Use real AD
export AD_DOMAIN=corp.example.com
export AD_SERVERS=dc1.corp.example.com,dc2.corp.example.com
export AD_BIND_DN="CN=svc-jenkins,OU=ServiceAccounts,DC=corp,DC=example,DC=com"
export AD_BIND_PASSWORD="..."

# Step 2: Deploy Jenkins (no deploy_ad needed - using real AD)
./scripts/k3d-manager deploy_jenkins --enable-ad --enable-vault
```

### Benefits

1. **Clear Intent** - Command name matches what you're deploying
2. **Prevents Errors** - No manual coordination of multiple variables
3. **Mutual Exclusivity** - Can't accidentally enable both LDAP and AD
4. **Backward Compatible** - Existing `deploy_ldap` unchanged
5. **DRY** - Shared code via directory service abstraction
6. **Future-Proof** - Easy to add real AD support later

### Migration Path

**Old way (error-prone):**
```bash
export LDAP_LDIF_FILE="${PWD}/scripts/etc/ldap/bootstrap-ad-schema.ldif"
export LDAP_BASE_DN="DC=corp,DC=example,DC=com"
export LDAP_BINDDN="cn=admin,DC=corp,DC=example,DC=com"
./scripts/k3d-manager deploy_ldap
./scripts/k3d-manager deploy_jenkins --enable-ldap
```

**New way (explicit):**
```bash
./scripts/k3d-manager deploy_ad
./scripts/k3d-manager deploy_jenkins --enable-ad --enable-vault
```

### File Changes Required

1. **scripts/plugins/ldap.sh** - Add `deploy_ad()` function
2. **scripts/plugins/jenkins.sh** - Add `--enable-ad` flag, add validation
3. **scripts/lib/dirservices/activedirectory.sh** - Add config helper (already exists)
4. **scripts/lib/dirservices/openldap.sh** - Update if needed (already exists)
5. **docs/guides/** - Update documentation with new commands
6. **CLAUDE.md** - Update project instructions

### Open Questions

1. Should `deploy_ad` support `--production` flag for real AD? Or separate command?
2. Should we deprecate manual `LDAP_LDIF_FILE` usage? Or keep for advanced users?
3. Do we need `undeploy_ad` command? Or just use `kubectl delete namespace directory`?

### Timeline

- **Phase 1**: Implement `deploy_ad` command (1-2 hours)
- **Phase 2**: Add `--enable-ad` flag to `deploy_jenkins` (1 hour)
- **Phase 3**: Testing and documentation (2-3 hours)
- **Phase 4**: Real AD support (future work, separate PR)
