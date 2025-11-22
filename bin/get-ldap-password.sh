#!/usr/bin/env bash
# Get LDAP user password from Vault
# Usage: ./bin/get-ldap-password.sh <username>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source system utilities for colored output
if [[ -f "$PROJECT_ROOT/scripts/lib/system.sh" ]]; then
    source "$PROJECT_ROOT/scripts/lib/system.sh"
else
    # Fallback if system.sh not available
    _info() { echo "[INFO] $*"; }
    _warn() { echo "[WARN] $*" >&2; }
    _err() { echo "[ERROR] $*" >&2; }
fi

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] <username>

Retrieve LDAP user password from Vault.

Arguments:
  username              LDAP username (e.g., chengkai.liang, jenkins-admin)

Options:
  -f, --field FIELD     Show specific field (password, username, dn, rotated_at)
  -j, --json            Output in JSON format
  -n, --vault-ns NS     Vault namespace (default: vault)
  -h, --help            Show this help message

Examples:
  # Get password only
  $(basename "$0") chengkai.liang

  # Get password (explicit)
  $(basename "$0") --field password chengkai.liang

  # Get all credential info as JSON
  $(basename "$0") --json jenkins-admin

  # Get rotation timestamp
  $(basename "$0") --field rotated_at test-user

  # Show full credential details
  $(basename "$0") --field "" chengkai.liang

Available users (default):
  - chengkai.liang
  - jenkins-admin
  - test-user

EOF
    exit 0
}

# Default values
VAULT_NS="vault"
FIELD="password"
JSON_OUTPUT=0
USERNAME=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        -f|--field)
            FIELD="$2"
            shift 2
            ;;
        -j|--json)
            JSON_OUTPUT=1
            shift
            ;;
        -n|--vault-ns)
            VAULT_NS="$2"
            shift 2
            ;;
        -*)
            _err "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            if [[ -z "$USERNAME" ]]; then
                USERNAME="$1"
            else
                _err "Too many arguments: $1"
                echo "Use --help for usage information"
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate username provided
if [[ -z "$USERNAME" ]]; then
    _err "Username required"
    echo ""
    echo "Usage: $(basename "$0") [OPTIONS] <username>"
    echo "Use --help for more information"
    exit 1
fi

# Check if vault pod exists
if ! kubectl get pod -n "$VAULT_NS" vault-0 >/dev/null 2>&1; then
    _err "Vault pod not found in namespace '$VAULT_NS'"
    _err "Is Vault deployed? Try: ./scripts/k3d-manager deploy_vault"
    exit 1
fi

VAULT_PATH="secret/ldap/users/${USERNAME}"

# Get Vault token from Kubernetes secret
VAULT_TOKEN=$(kubectl get secret -n "$VAULT_NS" vault-root -o jsonpath='{.data.root_token}' 2>/dev/null | base64 -d)
if [[ -z "$VAULT_TOKEN" ]]; then
    _err "Failed to retrieve Vault root token from secret vault-root"
    _err "Is Vault initialized? Check: kubectl get secret -n $VAULT_NS vault-root"
    exit 1
fi

# Retrieve credentials
if [[ $JSON_OUTPUT -eq 1 ]]; then
    _info "Retrieving credentials for user: $USERNAME (JSON format)"
    kubectl exec -n "$VAULT_NS" vault-0 -- sh -c \
        "VAULT_TOKEN='$VAULT_TOKEN' vault kv get -format=json $VAULT_PATH" 2>/dev/null | jq -r '.data.data'
    exit_code=$?
else
    if [[ -n "$FIELD" ]]; then
        _info "Retrieving $FIELD for user: $USERNAME"
        kubectl exec -n "$VAULT_NS" vault-0 -- sh -c \
            "VAULT_TOKEN='$VAULT_TOKEN' vault kv get -field=$FIELD $VAULT_PATH" 2>/dev/null
        exit_code=$?
    else
        _info "Retrieving all fields for user: $USERNAME"
        kubectl exec -n "$VAULT_NS" vault-0 -- sh -c \
            "VAULT_TOKEN='$VAULT_TOKEN' vault kv get $VAULT_PATH" 2>/dev/null
        exit_code=$?
    fi
fi

if [[ $exit_code -ne 0 ]]; then
    echo ""
    _err "Failed to retrieve credentials for user: $USERNAME"
    _err "Possible reasons:"
    _err "  - User does not exist in Vault path: $VAULT_PATH"
    _err "  - Vault is sealed or unavailable"
    _err "  - Insufficient permissions"
    echo ""
    _info "Available users can be listed with:"
    _info "  kubectl exec -n $VAULT_NS vault-0 -- sh -c \\"
    _info "    'VAULT_TOKEN=\$(cat /vault/secrets/root_token) vault kv list secret/ldap/users'"
    exit 1
fi
