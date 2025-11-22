# LDAP Bulk User Import

Utility to convert CSV user data to LDIF format and import users into OpenLDAP.

## Overview

The `ldap-bulk-import.sh` script automates the process of creating multiple LDAP users and groups from a CSV file. It supports both standard LDAP schema and Active Directory-compatible schema.

## Features

- **CSV to LDIF conversion**: Convert user data from CSV format to LDIF
- **Automatic group creation**: Groups mentioned in CSV are automatically created
- **Group membership management**: Users are automatically added to specified groups
- **Dual schema support**: Standard LDAP (basic) or AD-compatible schema
- **Password hash generation**: SSHA password hashing using `slappasswd`
- **Direct import**: Optional import directly into OpenLDAP cluster
- **Preview and validation**: View generated LDIF before importing

## Quick Start

### Basic Usage

```bash
# Generate LDIF from CSV
./bin/ldap-bulk-import.sh users.csv

# Generate and import into LDAP
./bin/ldap-bulk-import.sh --import users.csv

# Preview without importing
./bin/ldap-bulk-import.sh --dry-run users.csv
```

### CSV Format

Create a CSV file with the following header and format:

```csv
username,givenName,surname,email,uidNumber,gidNumber,groups
john.doe,John,Doe,john.doe@home.org,10100,10000,"developers,admins"
jane.smith,Jane,Smith,jane.smith@home.org,10101,10000,developers
bob.wilson,Bob,Wilson,bob.wilson@home.org,10102,10000,"developers,qa-team"
```

**Field descriptions:**

- `username`: LDAP username/uid (e.g., john.doe)
- `givenName`: First name (e.g., John)
- `surname`: Last name (e.g., Doe)
- `email`: Email address (e.g., john.doe@home.org)
- `uidNumber`: Unique POSIX user ID (e.g., 10100)
- `gidNumber`: POSIX group ID, usually 10000 for users
- `groups`: Comma-separated list of groups (use quotes if multiple)

**Requirements:**

- Header row is required
- All fields except `groups` are mandatory
- `uidNumber` must be unique for each user
- Groups field can be empty or contain one or more group names

## Examples

### Example 1: Standard LDAP Import

```bash
# Create CSV file
cat > users.csv << 'EOF'
username,givenName,surname,email,uidNumber,gidNumber,groups
john.doe,John,Doe,john.doe@home.org,10100,10000,"developers,admins"
jane.smith,Jane,Smith,jane.smith@home.org,10101,10000,developers
EOF

# Generate and import
./bin/ldap-bulk-import.sh --import users.csv
```

**Output:**
```
[INFO] Processing CSV file: users.csv
[INFO] Schema type: basic
[INFO] Base DN: dc=home,dc=org
[INFO] Generated 2 user entries
[INFO] Generating 2 group entries
[INFO] Import successful!
[INFO] Imported 2 users and 2 groups
```

### Example 2: Active Directory Schema

```bash
# Generate AD-compatible LDIF
./bin/ldap-bulk-import.sh \
  --schema ad \
  --base-dn "DC=corp,DC=example,DC=com" \
  --user-ou "OU=Users" \
  --group-ou "OU=Groups" \
  users.csv
```

**Generated LDIF:**
```ldif
dn: CN=John Doe,OU=Users,DC=corp,DC=example,DC=com
objectClass: top
objectClass: person
objectClass: inetOrgPerson
objectClass: organizationalPerson
cn: John Doe
sn: Doe
givenName: John
displayName: John Doe
sAMAccountName: john.doe
userPrincipalName: john.doe@corp.example.com
mail: john.doe@home.org
userPassword: {SSHA}...
```

### Example 3: Custom Configuration

```bash
# Import with custom settings
./bin/ldap-bulk-import.sh \
  --base-dn "dc=mycompany,dc=com" \
  --user-ou "ou=employees" \
  --group-ou "ou=teams" \
  --password "Welcome123!" \
  --namespace ldap \
  --import \
  employees.csv
```

### Example 4: Using Example CSV

An example CSV file is provided in `docs/examples/ldap-users-example.csv`:

```bash
# Test with example file
./bin/ldap-bulk-import.sh --dry-run docs/examples/ldap-users-example.csv

# Import example users
./bin/ldap-bulk-import.sh --import docs/examples/ldap-users-example.csv
```

## Command Options

```
Usage: ldap-bulk-import.sh [OPTIONS] <csv-file>

Options:
  -b, --base-dn DN      Base DN (default: dc=home,dc=org)
  -u, --user-ou OU      User OU (default: ou=users)
  -g, --group-ou OU     Group OU (default: ou=groups)
  -p, --password PASS   Default password (default: test1234)
  -s, --schema SCHEMA   Schema type: basic or ad (default: basic)
  -o, --output FILE     Output LDIF file (default: /tmp/bulk-import.ldif)
  -i, --import          Import LDIF into LDAP after generation
  -n, --namespace NS    Kubernetes namespace (default: directory)
  -d, --dry-run         Generate LDIF only, don't import
  -h, --help            Show help message
```

## Schema Types

### Basic Schema (default)

Standard LDAP schema using:
- `inetOrgPerson`, `posixAccount`, `organizationalPerson`
- Lowercase DNs: `cn=john.doe,ou=users,dc=home,dc=org`
- Attributes: `cn`, `sn`, `givenName`, `displayName`, `uid`, `uidNumber`, `gidNumber`, `homeDirectory`, `mail`, `userPassword`

**Use cases:**
- Standard OpenLDAP deployments
- POSIX-compliant authentication
- Traditional UNIX/Linux integration

### Active Directory Schema

AD-compatible schema using:
- `person`, `inetOrgPerson`, `organizationalPerson`
- Uppercase DNs: `CN=John Doe,OU=Users,DC=corp,DC=example,DC=com`
- Attributes: `cn`, `sn`, `givenName`, `displayName`, `sAMAccountName`, `userPrincipalName`, `mail`, `userPassword`

**Use cases:**
- Testing Jenkins AD integration with OpenLDAP
- Simulating Active Directory structure
- Windows-centric environments

## Password Management

### Default Password

Default password is `test1234` (suitable for testing only).

Change default password:
```bash
./bin/ldap-bulk-import.sh --password "SecurePassword123!" users.csv
```

### SSHA Hash Generation

If `slappasswd` is available, passwords are hashed using SSHA:
```bash
slappasswd -s "test1234" -h {SSHA}
```

If `slappasswd` is not available, a default test hash is used:
```
{SSHA}W6ph5Mm5Pz8GgiULbPgzG37mj9g1gLQy
```

## Group Management

### Automatic Group Creation

Groups mentioned in the `groups` field are automatically created:

**CSV:**
```csv
username,givenName,surname,email,uidNumber,gidNumber,groups
alice,Alice,Admin,alice@home.org,10100,10000,"admins,developers"
bob,Bob,Dev,bob@home.org,10101,10000,developers
```

**Generated groups:**
- `cn=admins,ou=groups,dc=home,dc=org` (member: alice)
- `cn=developers,ou=groups,dc=home,dc=org` (members: alice, bob)

### Group Membership

Users are automatically added to groups using `groupOfNames` objectClass with `member` attribute.

## Import Process

When using `--import` flag:

1. **Find LDAP pod**: Locates OpenLDAP pod in specified namespace
2. **Retrieve admin password**: Gets admin credentials from Kubernetes secret
3. **Copy LDIF**: Transfers generated LDIF to pod
4. **Import entries**: Executes `ldapadd` command
5. **Cleanup**: Removes temporary files

**Import command used:**
```bash
ldapadd -x -H ldap://localhost:1389 \
  -D "cn=admin,$BASE_DN" \
  -w "$ADMIN_PASSWORD" \
  -f /tmp/bulk-import.ldif
```

## Verification

### Check Imported Users

```bash
# List all users
kubectl exec -n directory $LDAP_POD -- \
  ldapsearch -x -b "ou=users,dc=home,dc=org" -LLL dn

# Search for specific user
kubectl exec -n directory $LDAP_POD -- \
  ldapsearch -x -b "ou=users,dc=home,dc=org" "(uid=john.doe)" -LLL
```

### Check Groups

```bash
# List all groups
kubectl exec -n directory $LDAP_POD -- \
  ldapsearch -x -b "ou=groups,dc=home,dc=org" -LLL dn

# Show group members
kubectl exec -n directory $LDAP_POD -- \
  ldapsearch -x -b "ou=groups,dc=home,dc=org" "(cn=developers)" -LLL member
```

### Test Authentication

```bash
# Test user bind
kubectl exec -n directory $LDAP_POD -- \
  ldapwhoami -x -H ldap://localhost:1389 \
  -D "cn=john.doe,ou=users,dc=home,dc=org" \
  -w "test1234"
```

## Troubleshooting

### Import Failures

**Error: "Already exists (68)"**
- User or group already exists
- Delete existing entry or use different username/uidNumber

**Error: "Invalid credentials (49)"**
- Admin password incorrect
- Check: `kubectl get secret -n directory openldap-admin-password`

**Error: "No such object (32)"**
- Base DN or OU doesn't exist
- Verify LDAP structure matches `--base-dn`, `--user-ou`, `--group-ou`

### Duplicate uidNumber

Each user must have unique `uidNumber`:

```bash
# Find duplicate uidNumbers in CSV
awk -F',' 'NR>1 {print $5}' users.csv | sort | uniq -d
```

### Missing slappasswd

If `slappasswd` is not available:

```bash
# macOS
brew install openldap

# Ubuntu/Debian
sudo apt-get install slapd ldap-utils

# Or use default test hash
# {SSHA}W6ph5Mm5Pz8GgiULbPgzG37mj9g1gLQy = "test1234"
```

## Best Practices

1. **Start with dry-run**: Always use `--dry-run` first to preview LDIF
2. **Validate CSV**: Check for duplicate uidNumbers and required fields
3. **Sequential uidNumbers**: Use sequential numbers starting from 10000+
4. **Consistent gidNumber**: Use 10000 for standard users
5. **Password security**: Change default password for non-test environments
6. **Backup before import**: Backup LDAP before bulk imports
7. **Test incrementally**: Import small batches first, then scale up

## Integration with Password Rotation

Users imported with this tool can be added to password rotation:

```bash
# Add users to rotation
export LDAP_USERS_TO_ROTATE="john.doe,jane.smith,bob.wilson"
./scripts/k3d-manager deploy_ldap --enable-vault

# Or manually trigger rotation
kubectl create job -n directory manual-rotation \
  --from=cronjob/ldap-password-rotator
```

See [LDAP Password Rotation](ldap-password-rotation.md) for details.

## See Also

- [LDAP Password Rotation](ldap-password-rotation.md)
- [Get LDAP Password Tool](../bin/get-ldap-password.sh)
- [Example CSV File](../examples/ldap-users-example.csv)
- [OpenLDAP Bootstrap Schema](../../scripts/etc/ldap/bootstrap-basic-schema.ldif)
- [Active Directory Schema](../../scripts/etc/ldap/bootstrap-ad-schema.ldif)
