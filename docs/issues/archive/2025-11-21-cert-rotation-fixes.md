# Jenkins Certificate Rotation - Fix Summary

**Date**: 2025-11-19
**Status**: ✅ RESOLVED

## Problem

Certificate rotation jobs were failing with `403 Forbidden` errors when attempting to authenticate with Vault to issue new certificates.

## Root Cause

The CronJob template (`jenkins-cert-rotator.yaml.tmpl`) used bash-style default value syntax like `${VAULT_PKI_PATH:-pki}` for environment variables. However, `envsubst` doesn't understand this syntax - it only does simple variable substitution. When variables weren't explicitly exported, `envsubst` left them unchanged as literal strings like `${VAULT_PKI_PATH:-pki}` in the final YAML.

This caused the rotation job pods to have incorrectly set environment variables, which broke Vault authentication.

## Solution

### 1. Export Variables with Defaults (scripts/plugins/jenkins.sh:1670-1677)

Added explicit variable exports with defaults before running `envsubst`:

```bash
# Ensure all template variables are exported with defaults for envsubst
# envsubst doesn't understand bash ${VAR:-default} syntax, so we must set defaults explicitly
export VAULT_PKI_PATH="${VAULT_PKI_PATH:-pki}"
export VAULT_PKI_ROLE_TTL="${VAULT_PKI_ROLE_TTL:-}"
export VAULT_NAMESPACE="${VAULT_NAMESPACE:-}"
export VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY:-}"
export VAULT_CACERT="${VAULT_CACERT:-}"
export JENKINS_CERT_ROTATOR_ALT_NAMES="${JENKINS_CERT_ROTATOR_ALT_NAMES:-}"
```

### 2. Simplified Template Syntax (scripts/etc/jenkins/jenkins-cert-rotator.yaml.tmpl)

Changed environment variable references from bash default syntax to simple substitution:

**Before**:
```yaml
- name: VAULT_PKI_PATH
  value: "${VAULT_PKI_PATH:-pki}"
```

**After**:
```yaml
- name: VAULT_PKI_PATH
  value: "${VAULT_PKI_PATH}"
```

## Verification

Certificate rotation tested and verified working:

1. **Vault Configuration**: Policy and Kubernetes auth role created correctly
   - Policy `jenkins-cert-rotator` exists with correct PKI permissions
   - K8s auth role bound to service account `jenkins-cert-rotator`

2. **Manual Job Tests**: Multiple rotation jobs completed successfully
   - No 403 authentication errors
   - Certificates successfully issued and updated
   - Jobs complete in ~10-15 seconds

3. **Certificate Rotation Confirmed**:
   ```
   Before:  serial=55B58C90C4058FD28F9D850CFD950F669F648035
   After:   serial=6D7A0416F1C624BBAF1636360C4FC56066C2F74A
   New TTL: 10 minutes (test configuration)
   ```

## Files Modified

1. `scripts/plugins/jenkins.sh` (lines 1670-1677)
   - Added variable exports with defaults

2. `scripts/etc/jenkins/jenkins-cert-rotator.yaml.tmpl` (lines 89-112)
   - Simplified template variable syntax

## Additional Context

During troubleshooting, we also:
- Fixed image compatibility for ARM64 (switched to `alpine:latest`)
- Added runtime tool installation in the CronJob script
- Improved Vault policy creation using file-based approach

## Known Issues

The `./scripts/k3d-manager test_cert_rotation` command still hangs when called through the dispatcher, but this is a separate issue from the actual rotation functionality. Direct testing via manual job creation works perfectly.

## Test Configuration Used

```bash
# /tmp/cert-rotation-test.env or scripts/etc/jenkins/cert-rotation-test.env
export VAULT_PKI_ROLE_TTL="10m"
export JENKINS_CERT_ROTATOR_RENEW_BEFORE="300"
export JENKINS_CERT_ROTATOR_SCHEDULE="*/2 * * * *"
export JENKINS_CERT_ROTATOR_ENABLED="1"
```

## Conclusion

✅ Jenkins certificate rotation is now fully functional
✅ Vault authentication working correctly
✅ Certificates rotate successfully
✅ Ready for production use with appropriate TTL settings
