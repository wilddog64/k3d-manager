# LDAP Password Configuration Bug - Root Cause and Fix Attempt

## Root Cause

The LDAP bind password is hardcoded into the Jenkins ConfigMap at deployment time instead of being read dynamically from a Kubernetes secret. This causes the password to become stale whenever:
1. LDAP is redeployed with a new password
2. The password is rotated in Vault
3. ESO syncs a new password to the K8s secret

## The Problem Flow

1. **Deployment time** (T=0):
   - LDAP deployed with password `OLD_PASS`
   - ESO syncs `OLD_PASS` to secret `jenkins-ldap-config`
   - Jenkins deployment reads `OLD_PASS` from environment variable
   - `envsubst` substitutes `${LDAP_BIND_PASSWORD}` → `OLD_PASS` in JCasC YAML
   - ConfigMap created with hardcoded `OLD_PASS`

2. **After LDAP redeployment** (T=later):
   - LDAP now has password `NEW_PASS`
   - ESO syncs `NEW_PASS` to secret `jenkins-ldap-config`
   - Jenkins ConfigMap still has hardcoded `OLD_PASS`
   - **Authentication fails!**

## Fix Attempt

Changed `scripts/etc/jenkins/values-ldap.yaml.tmpl` line 144:
```yaml
# Before:
managerPasswordSecret: "${LDAP_BIND_PASSWORD}"

# After:
managerPasswordSecret: "$${jenkins-ldap-config:LDAP_BIND_PASSWORD}"
```

The `$$` should prevent `envsubst` from expanding it, leaving `${jenkins-ldap-config:LDAP_BIND_PASSWORD}` for JCasC's Kubernetes secret provider.

## Current Status

After the fix, ConfigMap contains:
```yaml
managerPasswordSecret: "$${jenkins-ldap-config:LDAP_BIND_PASSWORD}"
```

But authentication still fails with "Invalid Credentials". This suggests:
1. Jenkins JCasC isn't recognizing the `$$` syntax
2. OR Jenkins is literally using the string `$$` as the password
3. OR the Kubernetes secret provider syntax is wrong

## Next Steps

Need to verify:
1. Correct JCasC Kubernetes secret provider syntax
2. Whether `$$` is the right escaping method for `envsubst`
3. Whether Jenkins Configuration as Code plugin supports K8s secret references
