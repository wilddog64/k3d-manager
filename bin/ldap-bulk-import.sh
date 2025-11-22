#!/usr/bin/env bash
# LDAP Bulk Import - Convert CSV to LDIF and import users
# Usage: ./bin/ldap-bulk-import.sh [OPTIONS] <csv-file>

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
    cat << 'EOF'
Usage: ldap-bulk-import.sh [OPTIONS] <csv-file>

Convert CSV user data to LDIF format and optionally import into OpenLDAP.

CSV Format:
  username,givenName,surname,email,uidNumber,gidNumber,groups

CSV Example:
  john.doe,John,Doe,john.doe@example.com,10100,10000,"developers,admins"
  jane.smith,Jane,Smith,jane.smith@example.com,10101,10000,developers

Options:
  -b, --base-dn DN      Base DN (default: dc=home,dc=org)
  -u, --user-ou OU      User OU (default: ou=users)
  -g, --group-ou OU     Group OU (default: ou=groups)
  -p, --password PASS   Default password for all users (default: test1234)
  -s, --schema SCHEMA   Schema type: basic or ad (default: basic)
  -o, --output FILE     Output LDIF file path (default: /tmp/bulk-import.ldif)
  -i, --import          Import LDIF into LDAP after generation
  -n, --namespace NS    Kubernetes namespace for LDAP (default: directory)
  -d, --dry-run         Generate LDIF only, don't import
  -h, --help            Show this help message

Schema Types:
  basic - Standard LDAP schema (inetOrgPerson, posixAccount)
  ad    - Active Directory-compatible schema (sAMAccountName, userPrincipalName)

Examples:
  # Generate LDIF only
  ldap-bulk-import.sh users.csv

  # Generate and import with custom base DN
  ldap-bulk-import.sh --import --base-dn "dc=corp,dc=example,dc=com" users.csv

  # Generate AD-compatible LDIF
  ldap-bulk-import.sh --schema ad --base-dn "DC=corp,DC=example,DC=com" users.csv

  # Import with custom password
  ldap-bulk-import.sh --import --password "SecurePass123!" users.csv

CSV Requirements:
  - Header row required: username,givenName,surname,email,uidNumber,gidNumber,groups
  - Groups field is comma-separated (use quotes if multiple)
  - uidNumber must be unique
  - gidNumber should match existing POSIX groups (usually 10000)

EOF
    exit 0
}

# Default values
BASE_DN="dc=home,dc=org"
USER_OU="ou=users"
GROUP_OU="ou=groups"
DEFAULT_PASSWORD="test1234"
SCHEMA="basic"
OUTPUT_FILE="/tmp/bulk-import.ldif"
IMPORT_MODE=0
DRY_RUN=0
LDAP_NAMESPACE="directory"
CSV_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        -b|--base-dn)
            BASE_DN="$2"
            shift 2
            ;;
        -u|--user-ou)
            USER_OU="$2"
            shift 2
            ;;
        -g|--group-ou)
            GROUP_OU="$2"
            shift 2
            ;;
        -p|--password)
            DEFAULT_PASSWORD="$2"
            shift 2
            ;;
        -s|--schema)
            SCHEMA="$2"
            if [[ "$SCHEMA" != "basic" && "$SCHEMA" != "ad" ]]; then
                _err "Invalid schema: $SCHEMA (must be 'basic' or 'ad')"
                exit 1
            fi
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -i|--import)
            IMPORT_MODE=1
            shift
            ;;
        -n|--namespace)
            LDAP_NAMESPACE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=1
            shift
            ;;
        -*)
            _err "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            if [[ -z "$CSV_FILE" ]]; then
                CSV_FILE="$1"
            else
                _err "Too many arguments: $1"
                echo "Use --help for usage information"
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate CSV file provided
if [[ -z "$CSV_FILE" ]]; then
    _err "CSV file required"
    echo ""
    echo "Usage: $(basename "$0") [OPTIONS] <csv-file>"
    echo "Use --help for more information"
    exit 1
fi

# Validate CSV file exists
if [[ ! -f "$CSV_FILE" ]]; then
    _err "CSV file not found: $CSV_FILE"
    exit 1
fi

# Generate SSHA password hash
generate_ssha_hash() {
    local password="$1"
    # Generate SSHA hash using slappasswd if available, otherwise use default test hash
    if command -v slappasswd >/dev/null 2>&1; then
        slappasswd -s "$password" -h {SSHA}
    else
        # Default test hash for password "test1234"
        echo "{SSHA}W6ph5Mm5Pz8GgiULbPgzG37mj9g1gLQy"
    fi
}

# Generate user entry in basic schema
generate_basic_user() {
    local username="$1"
    local given_name="$2"
    local surname="$3"
    local email="$4"
    local uid_number="$5"
    local gid_number="$6"
    local password_hash="$7"

    cat << EOF
# User: $username
dn: cn=$username,$USER_OU,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: top
cn: $username
sn: $surname
givenName: $given_name
displayName: $given_name $surname
uid: $username
uidNumber: $uid_number
gidNumber: $gid_number
homeDirectory: /home/$username
mail: $email
userPassword: $password_hash

EOF
}

# Generate user entry in AD-compatible schema
generate_ad_user() {
    local username="$1"
    local given_name="$2"
    local surname="$3"
    local email="$4"
    local uid_number="$5"
    local gid_number="$6"
    local password_hash="$7"

    # Extract domain from BASE_DN
    local domain
    domain=$(echo "$BASE_DN" | sed 's/DC=//gi' | sed 's/,/./g')

    cat << EOF
# User: $username
dn: CN=$given_name $surname,$USER_OU,$BASE_DN
objectClass: top
objectClass: person
objectClass: inetOrgPerson
objectClass: organizationalPerson
cn: $given_name $surname
sn: $surname
givenName: $given_name
displayName: $given_name $surname
sAMAccountName: $username
userPrincipalName: $username@$domain
mail: $email
userPassword: $password_hash

EOF
}

# Process CSV and generate LDIF
_info "Processing CSV file: $CSV_FILE"
_info "Schema type: $SCHEMA"
_info "Base DN: $BASE_DN"
_info "Output file: $OUTPUT_FILE"

# Generate password hash
PASSWORD_HASH=$(generate_ssha_hash "$DEFAULT_PASSWORD")

# Initialize output file
> "$OUTPUT_FILE"

# Track groups mentioned in CSV for group creation
declare -A GROUPS_NEEDED
declare -A GROUP_MEMBERS

# Read CSV and generate user entries
line_number=0
user_count=0

while IFS=',' read -r username given_name surname email uid_number gid_number groups_field; do
    line_number=$((line_number + 1))

    # Skip header row
    if [[ $line_number -eq 1 ]]; then
        if [[ "$username" != "username" ]]; then
            _warn "CSV missing header row or unexpected format"
            _warn "Expected: username,givenName,surname,email,uidNumber,gidNumber,groups"
        fi
        continue
    fi

    # Skip empty lines
    [[ -z "$username" ]] && continue

    # Trim whitespace
    username=$(echo "$username" | xargs)
    given_name=$(echo "$given_name" | xargs)
    surname=$(echo "$surname" | xargs)
    email=$(echo "$email" | xargs)
    uid_number=$(echo "$uid_number" | xargs)
    gid_number=$(echo "$gid_number" | xargs)
    groups_field=$(echo "$groups_field" | xargs | tr -d '"')

    # Validate required fields
    if [[ -z "$username" || -z "$given_name" || -z "$surname" || -z "$email" || -z "$uid_number" || -z "$gid_number" ]]; then
        _warn "Line $line_number: Missing required fields, skipping"
        continue
    fi

    # Generate user entry based on schema
    if [[ "$SCHEMA" == "ad" ]]; then
        generate_ad_user "$username" "$given_name" "$surname" "$email" "$uid_number" "$gid_number" "$PASSWORD_HASH" >> "$OUTPUT_FILE"
    else
        generate_basic_user "$username" "$given_name" "$surname" "$email" "$uid_number" "$gid_number" "$PASSWORD_HASH" >> "$OUTPUT_FILE"
    fi

    user_count=$((user_count + 1))

    # Track group memberships
    if [[ -n "$groups_field" ]]; then
        # Split groups by comma
        IFS=',' read -ra groups_array <<< "$groups_field"
        for group in "${groups_array[@]}"; do
            group=$(echo "$group" | xargs)
            GROUPS_NEEDED["$group"]=1

            # Build member DN based on schema
            if [[ "$SCHEMA" == "ad" ]]; then
                member_dn="CN=$given_name $surname,$USER_OU,$BASE_DN"
            else
                member_dn="cn=$username,$USER_OU,$BASE_DN"
            fi

            # Append to group members list
            if [[ -z "${GROUP_MEMBERS[$group]:-}" ]]; then
                GROUP_MEMBERS["$group"]="$member_dn"
            else
                GROUP_MEMBERS["$group"]="${GROUP_MEMBERS[$group]}|$member_dn"
            fi
        done
    fi
done < "$CSV_FILE"

_info "Generated $user_count user entries"

# Generate group entries
if [[ ${#GROUPS_NEEDED[@]} -gt 0 ]]; then
    _info "Generating ${#GROUPS_NEEDED[@]} group entries"

    echo "" >> "$OUTPUT_FILE"
    echo "# Groups" >> "$OUTPUT_FILE"

    for group in "${!GROUPS_NEEDED[@]}"; do
        if [[ "$SCHEMA" == "ad" ]]; then
            group_dn="CN=$group,$GROUP_OU,$BASE_DN"
        else
            group_dn="cn=$group,$GROUP_OU,$BASE_DN"
        fi

        echo "" >> "$OUTPUT_FILE"
        echo "# Group: $group" >> "$OUTPUT_FILE"
        echo "dn: $group_dn" >> "$OUTPUT_FILE"
        echo "objectClass: top" >> "$OUTPUT_FILE"
        echo "objectClass: groupOfNames" >> "$OUTPUT_FILE"

        if [[ "$SCHEMA" == "ad" ]]; then
            echo "cn: $group" >> "$OUTPUT_FILE"
        else
            echo "cn: $group" >> "$OUTPUT_FILE"
        fi

        echo "description: Auto-generated group from bulk import" >> "$OUTPUT_FILE"

        # Add members
        IFS='|' read -ra members <<< "${GROUP_MEMBERS[$group]}"
        for member in "${members[@]}"; do
            echo "member: $member" >> "$OUTPUT_FILE"
        done

        echo "" >> "$OUTPUT_FILE"
    done
fi

_info "LDIF generation complete: $OUTPUT_FILE"
_info "Summary: $user_count users, ${#GROUPS_NEEDED[@]} groups"

# Show preview
echo ""
_info "LDIF Preview (first 20 lines):"
head -20 "$OUTPUT_FILE"
if [[ $(wc -l < "$OUTPUT_FILE") -gt 20 ]]; then
    echo "..."
    echo "($(wc -l < "$OUTPUT_FILE") total lines)"
fi

# Import if requested
if [[ $IMPORT_MODE -eq 1 && $DRY_RUN -eq 0 ]]; then
    echo ""
    _info "Importing LDIF into LDAP namespace: $LDAP_NAMESPACE"

    # Find LDAP pod
    LDAP_POD=$(kubectl get pod -n "$LDAP_NAMESPACE" \
        -l app.kubernetes.io/name=openldap-bitnami \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    if [[ -z "$LDAP_POD" ]]; then
        _err "LDAP pod not found in namespace: $LDAP_NAMESPACE"
        _err "LDIF file saved to: $OUTPUT_FILE"
        _err "You can manually import with:"
        _err "  kubectl exec -n $LDAP_NAMESPACE \$LDAP_POD -- ldapadd -x -D \"\$ADMIN_DN\" -w \"\$ADMIN_PASSWORD\" -f /tmp/import.ldif"
        exit 1
    fi

    _info "Found LDAP pod: $LDAP_POD"

    # Get admin password
    ADMIN_PASSWORD=$(kubectl get secret -n "$LDAP_NAMESPACE" openldap-admin-password \
        -o jsonpath='{.data.LDAP_ADMIN_PASSWORD}' 2>/dev/null | base64 -d || true)

    if [[ -z "$ADMIN_PASSWORD" ]]; then
        _err "Failed to retrieve LDAP admin password"
        _err "LDIF file saved to: $OUTPUT_FILE"
        exit 1
    fi

    # Copy LDIF to pod
    _info "Copying LDIF to pod..."
    kubectl cp "$OUTPUT_FILE" "$LDAP_NAMESPACE/$LDAP_POD:/tmp/bulk-import.ldif"

    # Import LDIF
    _info "Importing entries..."
    if kubectl exec -n "$LDAP_NAMESPACE" "$LDAP_POD" -- \
        ldapadd -x -H ldap://localhost:1389 \
        -D "cn=admin,$BASE_DN" \
        -w "$ADMIN_PASSWORD" \
        -f /tmp/bulk-import.ldif; then
        _info "Import successful!"
        _info "Imported $user_count users and ${#GROUPS_NEEDED[@]} groups"
    else
        _err "Import failed. Check LDIF syntax or duplicate entries."
        _err "LDIF file saved to: $OUTPUT_FILE"
        exit 1
    fi

    # Cleanup
    kubectl exec -n "$LDAP_NAMESPACE" "$LDAP_POD" -- rm /tmp/bulk-import.ldif

elif [[ $DRY_RUN -eq 1 ]]; then
    _info "Dry run mode - LDIF generated but not imported"
    _info "To import manually, use: $0 --import $CSV_FILE"
else
    echo ""
    _info "To import this LDIF, use: $0 --import $CSV_FILE"
fi

exit 0
