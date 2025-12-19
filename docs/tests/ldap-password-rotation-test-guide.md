# Manual LDAP Password Rotation Test

## Step 1: Check current rotation timestamp
```bash
kubectl logs -n directory job/final-rotation-test | grep "test-user" -A2
```
You'll see the SHA256 hash of the current password and timestamp.

## Step 2: Run another rotation
```bash
kubectl create job -n directory manual-test --from=cronjob/ldap-password-rotator
sleep 10
kubectl logs -n directory job/manual-test | grep "test-user" -A2
```

## Step 3: Compare the hashes
The SHA256 hash shown for test-user should be DIFFERENT between the two runs,
proving the password changed.

## Step 4: Verify rotation count
```bash
kubectl get jobs -n directory -l app=ldap-password-rotator --sort-by=.metadata.creationTimestamp
```
Shows all rotation jobs that have run.

## What the logs show:
- `Generated password hash (SHA256): abc123...` - Hash of NEW password
- `✓ Updated LDAP password` - Password changed in OpenLDAP
- `✓ Updated Vault password (hash: abc123...)` - Same password stored in Vault
- `Password rotation complete: 3 succeeded, 0 failed` - All users rotated

## Expected behavior:
1. Each rotation generates a NEW random 20-character password
2. Password hash changes every time
3. Both LDAP and Vault get updated
4. Old password stops working immediately
5. New password works in LDAP
