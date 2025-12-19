#!/usr/bin/env bash
# scripts/lib/directory_service.sh
# Directory service abstraction layer for k3d-manager
# Provides unified interface for OpenLDAP, Active Directory, Azure AD, Okta, etc.

# Default provider: openldap (matches existing ldap.sh naming)
DIRECTORY_SERVICE_PROVIDER="${DIRECTORY_SERVICE_PROVIDER:-${DIRECTORY_SERVICE:-openldap}}"
DIRECTORY_SERVICE_PROVIDER_DIR="${SCRIPT_DIR}/lib/dirservices"

# Provider cache to avoid repeated sourcing
declare -Ag _DIRECTORY_SERVICE_PROVIDER_LOADED=()

function _directory_service_load_provider() {
   local provider="${1:-${DIRECTORY_SERVICE_PROVIDER}}"
   provider=$(printf '%s' "$provider" | tr '[:upper:]' '[:lower:]')

   if [[ -n "${_DIRECTORY_SERVICE_PROVIDER_LOADED[$provider]:-}" ]]; then
      return 0
   fi

   local provider_file="${DIRECTORY_SERVICE_PROVIDER_DIR}/${provider}.sh"
   if [[ ! -r "$provider_file" ]]; then
      _err "[directory-service] provider '$provider' not found at $provider_file"
   fi

   # shellcheck disable=SC1090
   source "$provider_file"
   _DIRECTORY_SERVICE_PROVIDER_LOADED[$provider]=1
}

function _directory_service_provider() {
   printf '%s' "${DIRECTORY_SERVICE_PROVIDER}"
}

# Initialize directory service (deploy if self-hosted like OpenLDAP)
# Args: provider-specific initialization parameters
# Returns: 0 on success
function dirservice_init() {
   local provider
   provider=$(_directory_service_provider)
   _directory_service_load_provider "$provider"

   local func="_dirservice_${provider}_init"
   if ! declare -f "$func" >/dev/null 2>&1; then
      _err "[directory-service] provider '$provider' does not implement ${func}"
   fi

   "$func" "$@"
}

# Create service account credentials in secret backend
# Args: secret_backend, secret_path, [provider-specific params]
# Returns: 0 on success
function dirservice_create_credentials() {
   local provider
   provider=$(_directory_service_provider)
   _directory_service_load_provider "$provider"

   local func="_dirservice_${provider}_create_credentials"
   if ! declare -f "$func" >/dev/null 2>&1; then
      _err "[directory-service] provider '$provider' does not implement ${func}"
   fi

   "$func" "$@"
}

# Generate JCasC securityRealm configuration
# Args: namespace, secret_name, output_file
# Returns: 0 on success, writes YAML to output_file
function dirservice_generate_jcasc() {
   local provider
   provider=$(_directory_service_provider)
   _directory_service_load_provider "$provider"

   local func="_dirservice_${provider}_generate_jcasc"
   if ! declare -f "$func" >/dev/null 2>&1; then
      _err "[directory-service] provider '$provider' does not implement ${func}"
   fi

   "$func" "$@"
}

# Generate environment variable configuration for Helm values
# Args: secret_name, output_file
# Returns: 0 on success, writes YAML snippet to output_file
function dirservice_generate_env_vars() {
   local provider
   provider=$(_directory_service_provider)
   _directory_service_load_provider "$provider"

   local func="_dirservice_${provider}_generate_env_vars"
   if ! declare -f "$func" >/dev/null 2>&1; then
      _err "[directory-service] provider '$provider' does not implement ${func}"
   fi

   "$func" "$@"
}

# Validate directory service configuration (reachability, credentials)
# Returns: 0 if valid, 1 if invalid
function dirservice_validate_config() {
   local provider
   provider=$(_directory_service_provider)
   _directory_service_load_provider "$provider"

   local func="_dirservice_${provider}_validate_config"
   if ! declare -f "$func" >/dev/null 2>&1; then
      _err "[directory-service] provider '$provider' does not implement ${func}"
   fi

   "$func" "$@"
}

# Query user's group memberships (for testing/validation)
# Args: username
# Returns: 0 on success, prints groups to stdout
function dirservice_get_groups() {
   local provider
   provider=$(_directory_service_provider)
   _directory_service_load_provider "$provider"

   local func="_dirservice_${provider}_get_groups"
   if ! declare -f "$func" >/dev/null 2>&1; then
      _err "[directory-service] provider '$provider' does not implement ${func}"
   fi

   "$func" "$@"
}

# Generate JCasC authorizationStrategy configuration
# Args: output_file, permissions_env_var
# Returns: 0 on success, writes YAML to output_file
function dirservice_generate_authz() {
   local provider
   provider=$(_directory_service_provider)
   _directory_service_load_provider "$provider"

   local func="_dirservice_${provider}_generate_authz"
   if ! declare -f "$func" >/dev/null 2>&1; then
      _err "[directory-service] provider '$provider' does not implement ${func}"
   fi

   "$func" "$@"
}

# Smoke test Jenkins login with directory credentials
# Args: jenkins_url, test_user, test_password
# Returns: 0 if login successful, 1 otherwise
function dirservice_smoke_test_login() {
   local provider
   provider=$(_directory_service_provider)
   _directory_service_load_provider "$provider"

   local func="_dirservice_${provider}_smoke_test_login"
   if ! declare -f "$func" >/dev/null 2>&1; then
      _err "[directory-service] provider '$provider' does not implement ${func}"
   fi

   "$func" "$@"
}

# Get provider-specific configuration
# Returns: provider-specific configuration information
function dirservice_config() {
   local provider
   provider=$(_directory_service_provider)
   _directory_service_load_provider "$provider"

   local func="_dirservice_${provider}_config"
   if ! declare -f "$func" >/dev/null 2>&1; then
      _err "[directory-service] provider '$provider' does not implement ${func}"
   fi

   "$func" "$@"
}
