#!/usr/bin/env bash
# scripts/lib/dirservices/activedirectory.sh
# Active Directory directory service provider implementation

# Load AD configuration variables
if [[ -r "${SCRIPT_DIR}/etc/ad/vars.sh" ]]; then
   # shellcheck disable=SC1091
   source "${SCRIPT_DIR}/etc/ad/vars.sh"
fi

# Initialize Active Directory directory service
# Args: namespace, release, [vault_ns, vault_release]
# Returns: 0 on success
function _dirservice_activedirectory_init() {
   local namespace="${1:-${JENKINS_NAMESPACE:-jenkins}}"
   local release="${2:-${JENKINS_RELEASE:-jenkins}}"
   local vault_ns="${3:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local vault_release="${4:-${VAULT_RELEASE:-$VAULT_RELEASE_DEFAULT}}"

   _info "[dirservice:activedirectory] initializing for ${namespace}/${release}"

   # Active Directory is external - no deployment needed
   # Instead, validate configuration and connectivity

   if ! _dirservice_activedirectory_validate_config; then
      _err "[dirservice:activedirectory] configuration validation failed"
      return 1
   fi

   # Store AD credentials in Vault for Jenkins to use
   if ! _dirservice_activedirectory_create_credentials "vault" "${AD_VAULT_SECRET_PATH}" "$vault_ns" "$vault_release"; then
      _err "[dirservice:activedirectory] failed to store credentials in Vault"
      return 1
   fi

   _info "[dirservice:activedirectory] initialization complete"
   return 0
}

# Create service account credentials in secret backend
# Args: secret_backend, secret_path, vault_ns, vault_release
# Returns: 0 on success
function _dirservice_activedirectory_create_credentials() {
   local secret_backend="${1:-vault}"
   local secret_path="${2:-ad/service-accounts/jenkins-admin}"
   local vault_ns="${3:-${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}}"
   local vault_release="${4:-${VAULT_RELEASE:-$VAULT_RELEASE_DEFAULT}}"

   _info "[dirservice:activedirectory] storing credentials at ${secret_path}"

   # Validate required credentials are present
   if [[ -z "${AD_BIND_DN}" ]]; then
      _err "[dirservice:activedirectory] AD_BIND_DN not set"
      return 1
   fi

   if [[ -z "${AD_BIND_PASSWORD}" ]]; then
      _err "[dirservice:activedirectory] AD_BIND_PASSWORD not set"
      return 1
   fi

   # Use secret backend abstraction to store credentials
   if declare -f secret_backend_put >/dev/null 2>&1; then
      export SECRET_BACKEND_PROVIDER="${secret_backend}"
      export VAULT_SECRET_BACKEND_NS="$vault_ns"
      export VAULT_SECRET_BACKEND_RELEASE="$vault_release"
      export VAULT_SECRET_BACKEND_MOUNT="${AD_VAULT_KV_MOUNT}"

      if ! secret_backend_put "$secret_path" \
         "${AD_USERNAME_KEY}=${AD_BIND_DN}" \
         "${AD_PASSWORD_KEY}=${AD_BIND_PASSWORD}" \
         "${AD_DOMAIN_KEY}=${AD_DOMAIN}" \
         "${AD_SERVERS_KEY}=${AD_SERVERS}"; then
         _err "[dirservice:activedirectory] failed to store credentials"
         return 1
      fi
   else
      _err "[dirservice:activedirectory] secret_backend_put function not available"
      return 1
   fi

   _info "[dirservice:activedirectory] credentials stored successfully"
   return 0
}

# Generate JCasC securityRealm configuration
# Args: namespace, secret_name, output_file
# Returns: 0 on success, writes YAML to output_file
function _dirservice_activedirectory_generate_jcasc() {
   local namespace="${1:?namespace required}"
   local secret_name="${2:?secret name required}"
   local output_file="${3:?output file required}"

   _info "[dirservice:activedirectory] generating JCasC security realm config"

   # Use baseline-proven Active Directory plugin configuration
   # with configurable values instead of hardcoded
   cat > "$output_file" <<EOF
securityRealm:
  activeDirectory:
    bindPassword: "\${file:/vault/secrets/ad-ldap-bind-password}"
    cache:
      size: ${AD_CACHE_SIZE}
      ttl: ${AD_CACHE_TTL}
    customDomain: true
    domains:
      - bindName: "\${file:/vault/secrets/ad-ldap-bind-username}"
        bindPassword: "\${file:/vault/secrets/ad-ldap-bind-password}"
        name: "${AD_DOMAIN}"
        tlsConfiguration: "${AD_TLS_CONFIG}"
    groupLookupStrategy: "${AD_GROUP_LOOKUP_STRATEGY}"
    internalUsersDatabase:
      jenkinsInternalUser: "\${JENKINS_ADMIN_USER}"
    removeIrrelevantGroups: ${AD_REMOVE_IRRELEVANT_GROUPS}
    requireTLS: true
EOF

   _info "[dirservice:activedirectory] JCasC config written to ${output_file}"
   return 0
}

# Generate environment variable configuration for Helm values
# Args: secret_name, output_file
# Returns: 0 on success, writes YAML snippet to output_file
function _dirservice_activedirectory_generate_env_vars() {
   local secret_name="${1:?secret name required}"
   local output_file="${2:?output file required}"

   _info "[dirservice:activedirectory] generating environment variables"

   # Active Directory uses Vault Agent file mounts instead of environment variables
   # The Active Directory plugin expects credentials as files, not env vars
   # So we return an empty/minimal config
   cat > "$output_file" <<EOF
# Active Directory uses Vault Agent file mounts for credentials
# No environment variables required for AD authentication
# Credentials are mounted as files:
#   - /vault/secrets/ad-ldap-bind-username
#   - /vault/secrets/ad-ldap-bind-password
EOF

   return 0
}

# Validate directory service configuration (reachability, credentials)
# Returns: 0 if valid, 1 if invalid
function _dirservice_activedirectory_validate_config() {
   _info "[dirservice:activedirectory] validating configuration"

   # Test mode bypass for development
   if [[ "${AD_TEST_MODE:-0}" == "1" ]]; then
      _info "[dirservice:activedirectory] test mode enabled - skipping connectivity validation"
      return 0
   fi

   # Check required variables
   if [[ -z "${AD_DOMAIN}" ]]; then
      _err "[dirservice:activedirectory] AD_DOMAIN not set"
      _err "  Example: export AD_DOMAIN=corp.example.com"
      return 1
   fi

   if [[ -z "${AD_SERVERS}" ]]; then
      _err "[dirservice:activedirectory] AD_SERVERS not set"
      _err "  Example: export AD_SERVERS=dc1.corp.example.com,dc2.corp.example.com"
      return 1
   fi

   if [[ -z "${AD_BIND_DN}" ]]; then
      _err "[dirservice:activedirectory] AD_BIND_DN not set"
      _err "  Example: export AD_BIND_DN='CN=svc-jenkins,OU=ServiceAccounts,DC=corp,DC=example,DC=com'"
      return 1
   fi

   if [[ -z "${AD_BIND_PASSWORD}" ]]; then
      _err "[dirservice:activedirectory] AD_BIND_PASSWORD not set"
      return 1
   fi

   # Test connectivity to first AD server
   local first_server="${AD_SERVERS%%,*}"
   local protocol="ldap"
   local port="${AD_PORT}"

   if [[ "${AD_USE_SSL}" == "1" ]]; then
      protocol="ldaps"
   fi

   _info "[dirservice:activedirectory] testing connectivity to ${first_server}:${port}"

   # Check if ldapsearch is available
   if ! command -v ldapsearch >/dev/null 2>&1; then
      _warn "[dirservice:activedirectory] ldapsearch not available - skipping connectivity test"
      _warn "  Install ldap-utils (Debian/Ubuntu) or openldap-clients (RHEL/Fedora) to enable validation"
      return 0
   fi

   # Test LDAP connectivity with timeout
   if ! timeout "${AD_CONNECT_TIMEOUT}" ldapsearch \
      -H "${protocol}://${first_server}:${port}" \
      -D "${AD_BIND_DN}" \
      -w "${AD_BIND_PASSWORD}" \
      -b "${AD_BASE_DN}" \
      -s base \
      "(objectClass=*)" \
      >/dev/null 2>&1; then
      _err "[dirservice:activedirectory] cannot connect to AD server ${first_server}:${port}"
      _err "  Troubleshooting:"
      _err "    1. Check if you're connected to corporate VPN"
      _err "    2. Verify server is reachable: ping ${first_server}"
      _err "    3. Test LDAP manually: ldapsearch -H ${protocol}://${first_server}:${port} -D '${AD_BIND_DN}' -W -b '${AD_BASE_DN}' -s base"
      _err "    4. Check firewall allows port ${port}"
      return 1
   fi

   _info "[dirservice:activedirectory] connectivity test passed"
   return 0
}

# Query user's group memberships (for testing/validation)
# Args: username
# Returns: 0 on success, prints groups to stdout
function _dirservice_activedirectory_get_groups() {
   local username="${1:?username required}"

   _info "[dirservice:activedirectory] querying groups for user: ${username}"

   # Test mode bypass
   if [[ "${AD_TEST_MODE:-0}" == "1" ]]; then
      echo "CN=Jenkins Admins,OU=Groups,${AD_BASE_DN}"
      echo "CN=IT Developers,OU=Groups,${AD_BASE_DN}"
      return 0
   fi

   # Check if ldapsearch is available
   if ! command -v ldapsearch >/dev/null 2>&1; then
      _err "[dirservice:activedirectory] ldapsearch command not found"
      return 1
   fi

   local first_server="${AD_SERVERS%%,*}"
   local protocol="ldap"
   local port="${AD_PORT}"

   if [[ "${AD_USE_SSL}" == "1" ]]; then
      protocol="ldaps"
   fi

   # Query user's memberOf attribute
   # Note: This doesn't use tokenGroups (binary attribute) which would be more efficient
   # but is harder to parse in shell. Jenkins Active Directory plugin handles tokenGroups natively.
   ldapsearch \
      -H "${protocol}://${first_server}:${port}" \
      -D "${AD_BIND_DN}" \
      -w "${AD_BIND_PASSWORD}" \
      -b "${AD_USER_SEARCH_BASE}" \
      "(sAMAccountName=${username})" \
      memberOf \
      | grep "^memberOf:" \
      | cut -d' ' -f2-
}

# Generate JCasC authorizationStrategy configuration
# Args: output_file, permissions_env_var
# Returns: 0 on success, writes YAML to output_file
function _dirservice_activedirectory_generate_authz() {
   local output_file="${1:?output file required}"
   local permissions_env="${2:-JENKINS_AUTHZ_PERMISSIONS}"

   _info "[dirservice:activedirectory] generating authorization strategy"

   # Use flat permissions format (baseline-compatible)
   # Supports both users and groups with explicit prefixes
   cat > "$output_file" <<'EOF'
authorizationStrategy:
  projectMatrix:
    permissions:
      - "Overall/Read:authenticated"
      - "Overall/Read:${JENKINS_ADMIN_USER}"
      - "Overall/Administer:${JENKINS_ADMIN_USER}"
EOF

   # Add additional permissions from environment variable if set
   if [[ -n "${!permissions_env}" ]]; then
      local perms="${!permissions_env}"
      # Split by comma and add each permission
      IFS=',' read -ra PERMS <<< "$perms"
      for perm in "${PERMS[@]}"; do
         echo "      - \"${perm}\"" >> "$output_file"
      done
   fi

   return 0
}

# Smoke test Jenkins login with directory credentials
# Args: jenkins_url, test_user, test_password
# Returns: 0 if login successful, 1 otherwise
function _dirservice_activedirectory_smoke_test_login() {
   local jenkins_url="${1:?Jenkins URL required}"
   local test_user="${2:?test user required}"
   local test_password="${3:?test password required}"

   _info "[dirservice:activedirectory] testing login for user: ${test_user}"

   # Check if curl is available
   if ! command -v curl >/dev/null 2>&1; then
      _err "[dirservice:activedirectory] curl command not found"
      return 1
   fi

   # Attempt to get Jenkins crumb (requires authentication)
   local crumb
   crumb=$(curl -s -u "${test_user}:${test_password}" \
      "${jenkins_url}/crumbIssuer/api/json" \
      | grep -o '"crumb":"[^"]*"' \
      | cut -d'"' -f4 2>/dev/null || true)

   if [[ -z "$crumb" ]]; then
      _err "[dirservice:activedirectory] failed to authenticate user: ${test_user}"
      _err "  This could mean:"
      _err "    1. Invalid credentials"
      _err "    2. User not found in AD"
      _err "    3. AD connection issue"
      _err "    4. Jenkins not properly configured for AD"
      return 1
   fi

   # Verify whoAmI
   local whoami
   whoami=$(curl -s -u "${test_user}:${test_password}" \
      -H "Jenkins-Crumb: $crumb" \
      "${jenkins_url}/me/api/json" \
      | grep -o '"id":"[^"]*"' \
      | cut -d'"' -f4 2>/dev/null || true)

   if [[ "$whoami" != "$test_user" ]]; then
      _err "[dirservice:activedirectory] user mismatch: expected ${test_user}, got ${whoami}"
      return 1
   fi

   _info "[dirservice:activedirectory] ✓ user ${test_user} authenticated successfully"
   return 0
}

# Get provider-specific configuration
# Returns: provider-specific configuration information
function _dirservice_activedirectory_config() {
   _info "[dirservice:activedirectory] configuration:"
   _info "  Domain: ${AD_DOMAIN:-<not set>}"
   _info "  Servers: ${AD_SERVERS:-<not set>}"
   _info "  Base DN: ${AD_BASE_DN:-<not set>}"
   _info "  Bind DN: ${AD_BIND_DN:-<not set>}"
   _info "  Use SSL: ${AD_USE_SSL:-1}"
   _info "  Port: ${AD_PORT:-636}"
   _info "  TLS Config: ${AD_TLS_CONFIG:-JDK_TRUSTSTORE}"
   _info "  Group Lookup: ${AD_GROUP_LOOKUP_STRATEGY:-TOKENGROUPS}"
   _info "  Vault Path: ${AD_VAULT_SECRET_PATH:-ad/service-accounts/jenkins-admin}"
   return 0
}
