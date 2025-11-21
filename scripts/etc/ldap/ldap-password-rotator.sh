#!/usr/bin/env bash
# LDAP Password Rotation Script
# Rotates passwords for LDAP users and updates Vault

set -euo pipefail

# Configuration from environment variables
LDAP_NAMESPACE="${LDAP_NAMESPACE:-directory}"
LDAP_POD_LABEL="${LDAP_POD_LABEL:-app.kubernetes.io/name=openldap}"
LDAP_PORT="${LDAP_PORT:-389}"
LDAP_BASE_DN="${LDAP_BASE_DN:-dc=home,dc=org}"
LDAP_ADMIN_DN="${LDAP_ADMIN_DN:-cn=ldap-admin,dc=home,dc=org}"
LDAP_USER_OU="${LDAP_USER_OU:-ou=users}"
VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"
VAULT_ADDR="${VAULT_ADDR:-http://vault.vault.svc:8200}"
VAULT_ROOT_TOKEN_SECRET="${VAULT_ROOT_TOKEN_SECRET:-vault-root}"
VAULT_ROOT_TOKEN_KEY="${VAULT_ROOT_TOKEN_KEY:-token}"

# Users to rotate (comma-separated)
USERS_TO_ROTATE="${USERS_TO_ROTATE:-chengkai.liang,jenkins-admin,test-user}"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Get LDAP pod name
get_ldap_pod() {
    kubectl get pod -n "$LDAP_NAMESPACE" -l "$LDAP_POD_LABEL" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || {
        error "Failed to find LDAP pod"
        return 1
    }
}

# Get LDAP admin password from K8s secret
get_ldap_admin_password() {
    kubectl get secret -n "$LDAP_NAMESPACE" openldap-admin \
        -o jsonpath='{.data.LDAP_ADMIN_PASSWORD}' 2>/dev/null | base64 -d || {
        error "Failed to get LDAP admin password"
        return 1
    }
}

# Get Vault root token
get_vault_token() {
    kubectl get secret -n "$VAULT_NAMESPACE" "$VAULT_ROOT_TOKEN_SECRET" \
        -o jsonpath="{.data.$VAULT_ROOT_TOKEN_KEY}" 2>/dev/null | base64 -d || {
        error "Failed to get Vault root token"
        return 1
    }
}

# Generate random password
generate_password() {
    openssl rand -base64 18 | tr -d '/+=' | head -c 20
}

# Update password in LDAP
update_ldap_password() {
    local user_dn="$1"
    local new_password="$2"
    local ldap_pod="$3"
    local admin_pass="$4"

    kubectl exec -n "$LDAP_NAMESPACE" "$ldap_pod" -- \
        ldappasswd -x -H "ldap://localhost:${LDAP_PORT}" \
        -D "$LDAP_ADMIN_DN" -w "$admin_pass" \
        -s "$new_password" "$user_dn" >/dev/null 2>&1
}

# Update password in Vault
update_vault_password() {
    local username="$1"
    local new_password="$2"
    local user_dn="$3"
    local vault_token="$4"

    local vault_path="secret/ldap/users/${username}"

    kubectl exec -n "$VAULT_NAMESPACE" vault-0 -- \
        env VAULT_TOKEN="$vault_token" VAULT_ADDR="$VAULT_ADDR" \
        vault kv put "$vault_path" \
        username="$username" \
        password="$new_password" \
        dn="$user_dn" \
        rotated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1
}

# Main rotation logic
main() {
    log "Starting LDAP password rotation"

    # Get required resources
    local ldap_pod
    ldap_pod=$(get_ldap_pod) || exit 1
    log "Found LDAP pod: $ldap_pod"

    local admin_pass
    admin_pass=$(get_ldap_admin_password) || exit 1
    log "Retrieved LDAP admin password"

    local vault_token
    vault_token=$(get_vault_token) || exit 1
    log "Retrieved Vault token"

    # Convert comma-separated users to array
    IFS=',' read -ra users <<< "$USERS_TO_ROTATE"

    local success_count=0
    local failure_count=0

    for user in "${users[@]}"; do
        user=$(echo "$user" | xargs) # trim whitespace
        local user_dn="cn=${user},${LDAP_USER_OU},${LDAP_BASE_DN}"

        log "Rotating password for: $user"

        # Generate new password
        local new_password
        new_password=$(generate_password)

        # Update LDAP
        if update_ldap_password "$user_dn" "$new_password" "$ldap_pod" "$admin_pass"; then
            log "  ✓ Updated LDAP password for $user"
        else
            error "  ✗ Failed to update LDAP password for $user"
            ((failure_count++))
            continue
        fi

        # Update Vault
        if update_vault_password "$user" "$new_password" "$user_dn" "$vault_token"; then
            log "  ✓ Updated Vault password for $user"
            ((success_count++))
        else
            error "  ✗ Failed to update Vault password for $user"
            ((failure_count++))
        fi
    done

    log "Password rotation complete: $success_count succeeded, $failure_count failed"

    if [ "$failure_count" -gt 0 ]; then
        exit 1
    fi
}

main "$@"
