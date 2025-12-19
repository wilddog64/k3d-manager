#!/usr/bin/env bash
# scripts/lib/secret_backend.sh
# Secret backend abstraction layer for k3d-manager
# Provides unified interface for Vault, Azure Key Vault, AWS Secrets Manager, etc.

# Default provider: vault
SECRET_BACKEND_PROVIDER="${SECRET_BACKEND_PROVIDER:-${SECRET_BACKEND:-vault}}"
SECRET_BACKEND_PROVIDER_DIR="${SCRIPT_DIR}/lib/secret_backends"

# Provider cache to avoid repeated sourcing
declare -Ag _SECRET_BACKEND_PROVIDER_LOADED=()

function _secret_backend_load_provider() {
   local provider="${1:-${SECRET_BACKEND_PROVIDER}}"
   provider=$(printf '%s' "$provider" | tr '[:upper:]' '[:lower:]')

   if [[ -n "${_SECRET_BACKEND_PROVIDER_LOADED[$provider]:-}" ]]; then
      return 0
   fi

   local provider_file="${SECRET_BACKEND_PROVIDER_DIR}/${provider}.sh"
   if [[ ! -r "$provider_file" ]]; then
      _err "[secret_backend] provider '$provider' not found at $provider_file"
   fi

   # shellcheck disable=SC1090
   source "$provider_file"
   _SECRET_BACKEND_PROVIDER_LOADED[$provider]=1
}

function _secret_backend_provider() {
   printf '%s' "${SECRET_BACKEND_PROVIDER}"
}

# Initialize secret backend (provider-specific setup)
# Usage: secret_backend_init [args...]
function secret_backend_init() {
   local provider
   provider=$(_secret_backend_provider)
   _secret_backend_load_provider "$provider"

   local func="_secret_backend_${provider}_init"
   if ! declare -f "$func" >/dev/null 2>&1; then
      _err "[secret_backend] provider '$provider' does not implement ${func}"
   fi

   "$func" "$@"
}

# Create or update a secret
# Usage: secret_backend_put <path> <key1>=<value1> [key2=value2 ...]
# Example: secret_backend_put "eso/jenkins-admin" username=admin password=secret123
function secret_backend_put() {
   local provider
   provider=$(_secret_backend_provider)
   _secret_backend_load_provider "$provider"

   local func="_secret_backend_${provider}_put"
   if ! declare -f "$func" >/dev/null 2>&1; then
      _err "[secret_backend] provider '$provider' does not implement ${func}"
   fi

   "$func" "$@"
}

# Read a secret value by key
# Usage: secret_backend_get <path> <key>
# Example: secret_backend_get "eso/jenkins-admin" username
function secret_backend_get() {
   local provider
   provider=$(_secret_backend_provider)
   _secret_backend_load_provider "$provider"

   local func="_secret_backend_${provider}_get"
   if ! declare -f "$func" >/dev/null 2>&1; then
      _err "[secret_backend] provider '$provider' does not implement ${func}"
   fi

   "$func" "$@"
}

# Read entire secret as JSON
# Usage: secret_backend_get_json <path>
# Example: secret_backend_get_json "eso/jenkins-admin"
function secret_backend_get_json() {
   local provider
   provider=$(_secret_backend_provider)
   _secret_backend_load_provider "$provider"

   local func="_secret_backend_${provider}_get_json"
   if ! declare -f "$func" >/dev/null 2>&1; then
      _err "[secret_backend] provider '$provider' does not implement ${func}"
   fi

   "$func" "$@"
}

# Check if secret exists
# Usage: secret_backend_exists <path>
# Example: secret_backend_exists "eso/jenkins-admin"
function secret_backend_exists() {
   local provider
   provider=$(_secret_backend_provider)
   _secret_backend_load_provider "$provider"

   local func="_secret_backend_${provider}_exists"
   if ! declare -f "$func" >/dev/null 2>&1; then
      _err "[secret_backend] provider '$provider' does not implement ${func}"
   fi

   "$func" "$@"
}

# Delete a secret
# Usage: secret_backend_delete <path>
# Example: secret_backend_delete "eso/jenkins-admin"
function secret_backend_delete() {
   local provider
   provider=$(_secret_backend_provider)
   _secret_backend_load_provider "$provider"

   local func="_secret_backend_${provider}_delete"
   if ! declare -f "$func" >/dev/null 2>&1; then
      _err "[secret_backend] provider '$provider' does not implement ${func}"
   fi

   "$func" "$@"
}

# Get provider-specific configuration (namespace, mount path, etc.)
# Usage: secret_backend_config <key>
# Example: secret_backend_config "namespace"
function secret_backend_config() {
   local provider
   provider=$(_secret_backend_provider)
   _secret_backend_load_provider "$provider"

   local func="_secret_backend_${provider}_config"
   if ! declare -f "$func" >/dev/null 2>&1; then
      _err "[secret_backend] provider '$provider' does not implement ${func}"
   fi

   "$func" "$@"
}
