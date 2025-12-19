#!/usr/bin/env bash
# scripts/etc/ad/vars.sh
# Active Directory configuration variables

# Active Directory Domain and Servers
export AD_DOMAIN="${AD_DOMAIN:-}"
export AD_SERVERS="${AD_SERVERS:-}"  # Comma-separated: dc1.corp.example.com,dc2.corp.example.com

# Base DN (auto-detected from domain if not provided)
# Example: corp.example.com -> DC=corp,DC=example,DC=com
if [[ -z "${AD_BASE_DN:-}" ]] && [[ -n "${AD_DOMAIN}" ]]; then
   AD_BASE_DN="DC=${AD_DOMAIN//./,DC=}"
fi
export AD_BASE_DN="${AD_BASE_DN:-}"

# LDAP Connection Settings
export AD_USE_SSL="${AD_USE_SSL:-1}"  # Use LDAPS by default
export AD_PORT="${AD_PORT:-636}"      # 636=LDAPS, 389=LDAP, 3269=GC SSL, 3268=GC

# TLS Configuration
# Options: JDK_TRUSTSTORE, TRUST_ALL_CERTIFICATES (insecure), or custom path
export AD_TLS_CONFIG="${AD_TLS_CONFIG:-JDK_TRUSTSTORE}"
export AD_TLS_CA_CERT="${AD_TLS_CA_CERT:-}"  # Path to custom CA certificate

# Service Account Credentials
export AD_BIND_DN="${AD_BIND_DN:-}"
export AD_BIND_PASSWORD="${AD_BIND_PASSWORD:-}"

# Search Bases
# Auto-detected from AD_BASE_DN if not provided
export AD_USER_SEARCH_BASE="${AD_USER_SEARCH_BASE:-OU=Users,${AD_BASE_DN}}"
export AD_GROUP_SEARCH_BASE="${AD_GROUP_SEARCH_BASE:-OU=Groups,${AD_BASE_DN}}"

# Cache Settings (for Jenkins Active Directory plugin)
export AD_CACHE_SIZE="${AD_CACHE_SIZE:-50}"
export AD_CACHE_TTL="${AD_CACHE_TTL:-3600}"  # seconds

# Group Lookup Strategy
# Options: TOKENGROUPS (AD-specific, fast), RECURSIVE (standard LDAP, slower)
export AD_GROUP_LOOKUP_STRATEGY="${AD_GROUP_LOOKUP_STRATEGY:-TOKENGROUPS}"

# Remove Irrelevant Groups
export AD_REMOVE_IRRELEVANT_GROUPS="${AD_REMOVE_IRRELEVANT_GROUPS:-false}"

# Vault Storage Paths
export AD_VAULT_SECRET_PATH="${AD_VAULT_SECRET_PATH:-ad/service-accounts/jenkins-admin}"
export AD_VAULT_KV_MOUNT="${AD_VAULT_KV_MOUNT:-secret}"

# Secret Keys
export AD_USERNAME_KEY="${AD_USERNAME_KEY:-username}"
export AD_PASSWORD_KEY="${AD_PASSWORD_KEY:-password}"
export AD_DOMAIN_KEY="${AD_DOMAIN_KEY:-domain}"
export AD_SERVERS_KEY="${AD_SERVERS_KEY:-servers}"

# Test Mode (bypasses connectivity checks for development)
export AD_TEST_MODE="${AD_TEST_MODE:-0}"

# Timeout Settings
export AD_CONNECT_TIMEOUT="${AD_CONNECT_TIMEOUT:-5}"  # seconds
export AD_BIND_TIMEOUT="${AD_BIND_TIMEOUT:-10}"       # seconds
