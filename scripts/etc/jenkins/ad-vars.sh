#!/usr/bin/env bash
# Active Directory configuration variables for production AD integration

# AD Domain and Server Configuration
export AD_DOMAIN="${AD_DOMAIN:-corp.example.com}"
export AD_SERVER="${AD_SERVER:-}"  # Comma-separated list of AD servers (optional, auto-discovered if empty)
export AD_SITE="${AD_SITE:-}"      # AD site name (optional)

# AD Service Account Vault Path
export AD_VAULT_PATH="${AD_VAULT_PATH:-secret/data/jenkins/ad-credentials}"
export AD_USERNAME_KEY="${AD_USERNAME_KEY:-username}"
export AD_PASSWORD_KEY="${AD_PASSWORD_KEY:-password}"

# AD Connection Settings
export AD_REQUIRE_TLS="${AD_REQUIRE_TLS:-true}"
export AD_START_TLS="${AD_START_TLS:-false}"
export AD_TLS_CONFIG="${AD_TLS_CONFIG:-TRUST_ALL_CERTIFICATES}"  # Options: TRUST_ALL_CERTIFICATES, JDK_TRUSTSTORE, CUSTOM_TRUSTSTORE

# AD Group Settings
export AD_ADMIN_GROUP="${AD_ADMIN_GROUP:-Domain Admins}"
export AD_GROUP_LOOKUP_STRATEGY="${AD_GROUP_LOOKUP_STRATEGY:-RECURSIVE}"  # Options: RECURSIVE, TOKENGROUPS, CHAIN
export AD_REMOVE_IRRELEVANT_GROUPS="${AD_REMOVE_IRRELEVANT_GROUPS:-false}"

# AD Cache Settings
export AD_CACHE_SIZE="${AD_CACHE_SIZE:-100}"
export AD_CACHE_TTL="${AD_CACHE_TTL:-3600}"

# AD Custom Domain (set to true if using custom domain configuration)
export AD_CUSTOM_DOMAIN="${AD_CUSTOM_DOMAIN:-true}"
