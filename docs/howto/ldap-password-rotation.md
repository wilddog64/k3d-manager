# LDAP Password Rotation

Automated password rotation for LDAP users using Kubernetes CronJob.

## Overview

The LDAP password rotation feature automatically rotates passwords for configured LDAP users on a scheduled basis. Rotated passwords are:
- Updated in OpenLDAP using `ldappasswd`
- Stored in Vault with rotation timestamp
- Logged with SHA256 hash for audit trail

## Deployment

Password rotation is automatically deployed when LDAP is enabled with Vault:

```bash
./scripts/k3d-manager deploy_ldap --enable-vault
```

## Configuration

### Environment Variables

Configure rotation behavior before deployment:

```bash
# Schedule (cron format)
export LDAP_PASSWORD_ROTATION_SCHEDULE="0 0 1 * *"  # Monthly (default)

# Users to rotate (comma-separated)
export LDAP_USERS_TO_ROTATE="user1,user2,user3"

# Container image
export LDAP_PASSWORD_ROTATOR_IMAGE="docker.io/bitnami/kubectl:latest"

# LDAP port (internal)
export LDAP_PASSWORD_ROTATION_PORT="1389"
```

### Common Schedules

| Schedule | Cron Expression | Description |
|----------|----------------|-------------|
| Hourly | `0 * * * *` | Top of every hour |
| Daily | `0 0 * * *` | Midnight daily |
| Weekly | `0 0 * * 0` | Sunday midnight |
| Bi-weekly | `0 0 1,15 * *` | 1st and 15th |
| Monthly | `0 0 1 * *` | 1st of month (default) |
| Quarterly | `0 0 1 */3 *` | Every 3 months |

## Manual Rotation

Trigger an immediate rotation:

```bash
kubectl create job -n directory manual-rotation \
  --from=cronjob/ldap-password-rotator
```

View rotation logs:

```bash
kubectl logs -n directory job/manual-rotation
```

## Rotation Output

Each rotation generates output with SHA256 password hashes:

```
[2025-11-21 23:51:06] Starting LDAP password rotation
[2025-11-21 23:51:06] Found LDAP pod: openldap-openldap-bitnami-xxxxx
[2025-11-21 23:51:06] Retrieved LDAP admin password
[2025-11-21 23:51:06] Retrieved Vault token
[2025-11-21 23:51:06] Rotating password for: test-user
[2025-11-21 23:51:06]   Generated password hash (SHA256): 75ec5e4a15c0922c...
[2025-11-21 23:51:06]   ✓ Updated LDAP password for test-user
[2025-11-21 23:51:06]   ✓ Updated Vault password for test-user (hash: 75ec5e4a15c0922c...)
[2025-11-21 23:51:06] Password rotation complete: 3 succeeded, 0 failed
```

## Verification

### Check Rotation History

List all completed rotations:

```bash
kubectl get jobs -n directory -l app=ldap-password-rotator
```

### View Specific Rotation

```bash
kubectl logs -n directory job/<job-name>
```

### Check Vault Storage

Passwords are stored in Vault at `secret/ldap/users/<username>`:

```bash
kubectl exec -n vault vault-0 -- \
  vault kv get secret/ldap/users/test-user
```

Returns:
- `username`: LDAP username
- `password`: Current password
- `dn`: User's LDAP DN
- `rotated_at`: ISO 8601 timestamp

### Test Password

Test LDAP authentication with rotated password:

```bash
LDAP_POD=$(kubectl get pod -n directory \
  -l app.kubernetes.io/name=openldap-bitnami \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n directory $LDAP_POD -- \
  ldapwhoami -x -H ldap://localhost:1389 \
  -D "cn=test-user,ou=users,dc=home,dc=org" \
  -w "<password-from-vault>"
```

## Architecture

### Components

- **CronJob**: `ldap-password-rotator` - Scheduled rotation job
- **ConfigMap**: `ldap-password-rotator` - Rotation script
- **ServiceAccount**: `ldap-password-rotator` - RBAC identity
- **Roles**:
  - `ldap-password-rotator` (directory namespace) - LDAP access
  - `ldap-password-rotator-vault` (vault namespace) - Vault access

### Permissions

The rotation job requires cross-namespace RBAC:

**Directory namespace:**
- `pods`: get, list (find LDAP pod)
- `pods/exec`: create (run ldappasswd)
- `secrets`: get (LDAP admin password)

**Vault namespace:**
- `pods`: get (find vault pod)
- `pods/exec`: create (run vault commands)
- `secrets`: get (Vault root token)

### Password Generation

Passwords are generated using:
```bash
openssl rand -base64 18 | tr -d '/+=' | head -c 20
```

Results in 20-character alphanumeric passwords.

## Troubleshooting

### Rotation Fails

Check job logs for errors:

```bash
kubectl logs -n directory job/<job-name>
```

Common issues:
- LDAP pod not found: Check `LDAP_POD_LABEL` matches actual pod labels
- Permission denied: Verify RBAC roles and bindings
- Vault connection failed: Check `VAULT_ADDR` and Vault availability

### View CronJob Status

```bash
kubectl get cronjob -n directory ldap-password-rotator
```

### Disable Rotation

Set before deployment:

```bash
export LDAP_PASSWORD_ROTATOR_ENABLED=0
./scripts/k3d-manager deploy_ldap --enable-vault
```

Or delete after deployment:

```bash
kubectl delete cronjob -n directory ldap-password-rotator
```

## Security Notes

- Passwords are never logged in plain text (SHA256 hash only)
- Root token access is temporary (pod lifetime only)
- RBAC limits rotation job to specific namespaces and resources
- Old passwords are immediately invalidated in LDAP
- Rotation timestamp stored in Vault for audit trail

## See Also

- [LDAP Password Rotation Test Results](../tests/ldap-password-rotation-test-results-2025-11-21.md)
- [LDAP Password Rotation Test Guide](../tests/ldap-password-rotation-test-guide.md)
- [LDAP Configuration](../../scripts/etc/ldap/vars.sh)
