# Certificate Rotation Validation Test Plan

**Date**: 2025-11-17
**Purpose**: Validate Jenkins certificate auto-rotation functionality end-to-end
**Status**: Ready to Execute
**Effort**: 2-3 hours

---

## Overview

This test plan validates that the Jenkins certificate rotation CronJob:
1. Detects expiring certificates
2. Mints new certificates from Vault PKI
3. Updates Kubernetes secrets
4. Revokes old certificates in Vault
5. Handles errors gracefully

---

## Prerequisites

- k3d cluster running or ready to create
- Local kubectl configured
- No existing Jenkins deployment
- ~30 minutes of continuous testing time

---

## Test Environment Setup

### Step 1: Configure Short-Lived Certificates for Testing

Create test configuration file:

```bash
# Create test config
cat > /tmp/cert-rotation-test.env <<'EOF'
# Short-lived certs for rapid testing
export VAULT_PKI_ROLE_TTL="10m"                    # Cert lifetime: 10 minutes
export JENKINS_CERT_ROTATOR_RENEW_BEFORE="300"     # Renew when 5 min remaining
export JENKINS_CERT_ROTATOR_SCHEDULE="*/2 * * * *" # Check every 2 minutes

# Keep other defaults
export JENKINS_CERT_ROTATOR_ENABLED="1"
export JENKINS_CERT_ROTATOR_IMAGE="docker.io/google/cloud-sdk:slim"
EOF

# Load config
source /tmp/cert-rotation-test.env
```

**Why these values:**
- 10-minute cert lifetime allows full rotation test in ~15 minutes
- 5-minute renewal threshold ensures rotation happens before expiry
- 2-minute check interval catches rotation quickly

---

### Step 2: Deploy Test Environment

```bash
# Deploy Jenkins with Vault and short-lived certs
./scripts/k3d-manager deploy_jenkins --enable-vault

# Wait for Jenkins to be ready
kubectl rollout status deployment/jenkins -n jenkins --timeout=10m
```

**Expected:** Jenkins deploys successfully with initial certificate.

---

## Test Cases

### Test Case 1: Initial Certificate Verification

**Objective:** Verify initial certificate is issued correctly

```bash
# 1.1: Check cert secret exists
kubectl get secret jenkins-tls -n istio-system

# Expected: Secret exists with tls.crt, tls.key, ca.crt

# 1.2: Extract and examine certificate
kubectl get secret jenkins-tls -n istio-system -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -noout -text

# Expected output should show:
# - Subject: CN=jenkins.dev.local.me
# - Validity: 10 minutes from now
# - Issuer: Vault PKI CA

# 1.3: Get cert serial number (save for later)
INITIAL_SERIAL=$(kubectl get secret jenkins-tls -n istio-system \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | \
  openssl x509 -noout -serial | cut -d= -f2)

echo "Initial cert serial: $INITIAL_SERIAL"

# 1.4: Check cert expiry time
kubectl get secret jenkins-tls -n istio-system -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -noout -dates

# Expected:
# notBefore: <current time>
# notAfter: <current time + 10 minutes>
```

**Success Criteria:**
- ✅ Secret exists in istio-system namespace
- ✅ Certificate has 10-minute validity
- ✅ Serial number captured for comparison

---

### Test Case 2: CronJob Deployment Verification

**Objective:** Verify cert rotator CronJob is deployed and configured

```bash
# 2.1: Check CronJob exists
kubectl get cronjob jenkins-cert-rotator -n jenkins

# Expected: CronJob exists with schedule "*/2 * * * *"

# 2.2: Check CronJob configuration
kubectl get cronjob jenkins-cert-rotator -n jenkins -o yaml

# Verify:
# - schedule: "*/2 * * * *"
# - image: docker.io/google/cloud-sdk:slim
# - env vars set correctly (VAULT_ADDR, VAULT_PKI_ROLE, etc.)

# 2.3: Check ServiceAccount and RBAC
kubectl get serviceaccount jenkins-cert-rotator -n jenkins
kubectl get role jenkins-cert-rotator -n istio-system
kubectl get rolebinding jenkins-cert-rotator -n istio-system

# Expected: All resources exist

# 2.4: Verify ConfigMap with scripts
kubectl get configmap jenkins-cert-rotator -n jenkins
kubectl get configmap jenkins-cert-rotator -n jenkins \
  -o jsonpath='{.binaryData.cert-rotator\.sh}' | base64 -d | head -20

# Expected: ConfigMap contains cert-rotator.sh and vault_pki.sh
```

**Success Criteria:**
- ✅ CronJob configured with 2-minute schedule
- ✅ ServiceAccount and RBAC configured correctly
- ✅ Scripts embedded in ConfigMap

---

### Test Case 3: Manual Rotation Test

**Objective:** Trigger rotation manually before waiting for CronJob

```bash
# 3.1: Create manual job from CronJob
kubectl create job manual-cert-rotation-test \
  --from=cronjob/jenkins-cert-rotator -n jenkins

# 3.2: Watch job execution
kubectl logs -n jenkins job/manual-cert-rotation-test -f

# Expected log output:
# [INFO] Certificate for istio-system/jenkins-tls is valid for another XXXs; skipping rotation
# (because cert was just issued)

# 3.3: Check job completion
kubectl get job manual-cert-rotation-test -n jenkins

# Expected: Completions: 1/1

# 3.4: Clean up manual job
kubectl delete job manual-cert-rotation-test -n jenkins
```

**Success Criteria:**
- ✅ Job runs successfully
- ✅ Logs show cert is valid (too early to rotate)
- ✅ No errors in execution

---

### Test Case 4: Wait for Rotation Window

**Objective:** Wait until cert is within renewal threshold

```bash
# 4.1: Calculate when rotation should happen
# Cert lifetime: 10 min = 600 seconds
# Renew threshold: 5 min = 300 seconds
# Rotation window opens at: 5 minutes after issuance

echo "Waiting for rotation window (certificate must be < 5 min to expiry)..."
echo "Current time: $(date)"
echo "Rotation should occur after: $(date -d '+5 minutes' 2>/dev/null || date -v+5M)"

# 4.2: Monitor certificate age
while true; do
  REMAINING=$(kubectl get secret jenkins-tls -n istio-system \
    -o jsonpath='{.data.tls\.crt}' | base64 -d | \
    openssl x509 -noout -enddate | cut -d= -f2 | \
    xargs -I{} date -d {} +%s 2>/dev/null || echo "0")

  NOW=$(date +%s)
  DIFF=$((REMAINING - NOW))

  if [ $DIFF -lt 300 ]; then
    echo "Certificate within renewal threshold! ($DIFF seconds remaining)"
    break
  fi

  echo "Waiting... ($DIFF seconds until renewal threshold)"
  sleep 30
done
```

**Alternative (faster test):**
```bash
# If you don't want to wait, force rotation by deleting the secret
# WARNING: This causes brief TLS downtime
kubectl delete secret jenkins-tls -n istio-system

# Wait for next CronJob run (max 2 minutes)
# The rotator will see missing secret and issue new one
```

---

### Test Case 5: Automatic Rotation Verification

**Objective:** Verify CronJob detects renewal window and rotates cert

```bash
# 5.1: Watch for CronJob execution
kubectl get jobs -n jenkins -w

# Expected: New job appears every 2 minutes
# One of them should complete the rotation

# 5.2: Get latest rotation job
ROTATION_JOB=$(kubectl get jobs -n jenkins \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1].metadata.name}')

echo "Latest rotation job: $ROTATION_JOB"

# 5.3: Check rotation logs
kubectl logs -n jenkins job/$ROTATION_JOB

# Expected log output:
# [INFO] Certificate for istio-system/jenkins-tls expires in XXs (threshold 300s); rotating
# [INFO] Updated TLS secret istio-system/jenkins-tls

# 5.4: Verify new certificate issued
NEW_SERIAL=$(kubectl get secret jenkins-tls -n istio-system \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | \
  openssl x509 -noout -serial | cut -d= -f2)

echo "Initial serial: $INITIAL_SERIAL"
echo "New serial:     $NEW_SERIAL"

if [ "$INITIAL_SERIAL" != "$NEW_SERIAL" ]; then
  echo "✅ Certificate rotated successfully!"
else
  echo "❌ Certificate serial unchanged - rotation failed!"
fi

# 5.5: Verify new cert validity
kubectl get secret jenkins-tls -n istio-system \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | \
  openssl x509 -noout -dates

# Expected: notAfter should be ~10 minutes from now (fresh cert)
```

**Success Criteria:**
- ✅ CronJob detects expiring certificate
- ✅ New certificate issued with different serial
- ✅ Secret updated in Kubernetes
- ✅ New cert has fresh validity period

---

### Test Case 6: Old Certificate Revocation

**Objective:** Verify old certificate is revoked in Vault

```bash
# 6.1: Check Vault for revoked certificates
kubectl exec -n vault vault-0 -- \
  vault list pki/certs/revoked

# Expected: Should include the old serial number (without colons)
# Format: XX-XX-XX-XX-XX-... -> XXXXXXXXXX...

# 6.2: Verify old cert serial in revoked list
OLD_SERIAL_NORMALIZED=$(echo $INITIAL_SERIAL | tr -d ':' | tr '[:lower:]' '[:upper:]')
echo "Normalized old serial: $OLD_SERIAL_NORMALIZED"

kubectl exec -n vault vault-0 -- \
  vault list pki/certs/revoked | grep -i "$OLD_SERIAL_NORMALIZED"

# Expected: Match found

# 6.3: Read revocation details
kubectl exec -n vault vault-0 -- \
  vault read pki/cert/$OLD_SERIAL_NORMALIZED

# Expected: Should show revocation time and reason
```

**Success Criteria:**
- ✅ Old certificate serial appears in Vault's revoked list
- ✅ Revocation timestamp is recent (within test window)

---

### Test Case 7: Jenkins Service Continuity

**Objective:** Verify Jenkins continues serving HTTPS without interruption

```bash
# 7.1: Test Jenkins UI accessibility during rotation
# Run this in a separate terminal BEFORE rotation starts

while true; do
  STATUS=$(curl -k -s -o /dev/null -w "%{http_code}" https://jenkins.dev.local.me/login)
  if [ "$STATUS" == "200" ]; then
    echo "$(date): ✅ Jenkins accessible (HTTP $STATUS)"
  else
    echo "$(date): ❌ Jenkins unreachable (HTTP $STATUS)"
  fi
  sleep 5
done

# Expected: No 503 or connection errors during rotation

# 7.2: Check Jenkins logs for TLS errors
kubectl logs -n jenkins deployment/jenkins --since=10m | grep -i "tls\|certificate\|ssl"

# Expected: No certificate errors or warnings

# 7.3: Verify Istio Gateway picks up new cert
kubectl get secret jenkins-tls -n istio-system \
  -o jsonpath='{.metadata.annotations}'

# Check for managed-at annotation update
```

**Success Criteria:**
- ✅ No HTTP errors during rotation
- ✅ No TLS/certificate errors in Jenkins logs
- ✅ Istio Gateway continues serving HTTPS

---

### Test Case 8: Error Handling Tests

**Objective:** Verify graceful handling of error conditions

#### 8.1: Vault Unreachable

```bash
# Simulate Vault unavailability
kubectl scale deployment vault -n vault --replicas=0

# Trigger manual rotation
kubectl create job test-vault-down --from=cronjob/jenkins-cert-rotator -n jenkins

# Check logs
kubectl logs -n jenkins job/test-vault-down

# Expected: Error message about Vault connection failure
# Should NOT crash or leave secrets in bad state

# Restore Vault
kubectl scale deployment vault -n vault --replicas=1
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n vault --timeout=2m

# Clean up
kubectl delete job test-vault-down -n jenkins
```

#### 8.2: Missing kubectl

```bash
# This is hard to test in the pod, but verify error handling exists
kubectl get configmap jenkins-cert-rotator -n jenkins \
  -o jsonpath='{.binaryData.cert-rotator\.sh}' | base64 -d | \
  grep -A5 "discover_kubectl"

# Expected: Should show error handling for missing kubectl
```

#### 8.3: RBAC Permission Denied

```bash
# Remove secret permissions temporarily
kubectl delete rolebinding jenkins-cert-rotator -n istio-system

# Trigger rotation
kubectl create job test-rbac-denied --from=cronjob/jenkins-cert-rotator -n jenkins

# Check logs
kubectl logs -n jenkins job/test-rbac-denied

# Expected: Error about permission denied when updating secret

# Restore permissions
kubectl apply -f <(kubectl create rolebinding jenkins-cert-rotator \
  --role=jenkins-cert-rotator \
  --serviceaccount=jenkins:jenkins-cert-rotator \
  -n istio-system --dry-run=client -o yaml)

# Clean up
kubectl delete job test-rbac-denied -n jenkins
```

**Success Criteria:**
- ✅ Errors are logged clearly
- ✅ Jobs fail gracefully (no crash loops)
- ✅ Secrets not corrupted on error

---

## Test Results Documentation

### Test Execution Log Template

```markdown
## Certificate Rotation Validation - Test Results

**Date**: YYYY-MM-DD
**Tester**: [Your Name]
**Environment**: k3d / k3s
**Duration**: X hours

### Test Case Results

| Test Case | Status | Notes |
|-----------|--------|-------|
| TC1: Initial Certificate | ✅/❌ | |
| TC2: CronJob Deployment | ✅/❌ | |
| TC3: Manual Rotation | ✅/❌ | |
| TC4: Wait for Rotation Window | ✅/❌ | |
| TC5: Automatic Rotation | ✅/❌ | |
| TC6: Old Cert Revocation | ✅/❌ | |
| TC7: Service Continuity | ✅/❌ | |
| TC8: Error Handling | ✅/❌ | |

### Issues Found

1. [Issue description]
   - Severity: High/Medium/Low
   - Workaround: [if any]
   - Fix required: [yes/no]

### Observations

- [Any notable observations]
- [Performance notes]
- [Improvement suggestions]

### Conclusion

- [ ] Certificate rotation works as designed
- [ ] No blocking issues found
- [ ] Safe for production use
- [ ] Documentation updates needed (list below)
```

---

## Success Criteria Summary

**Overall Test PASSES if:**
1. ✅ Initial certificate issued successfully
2. ✅ CronJob deployed and configured correctly
3. ✅ Manual rotation job executes without errors
4. ✅ Automatic rotation occurs when cert expires
5. ✅ New certificate has different serial number
6. ✅ Old certificate revoked in Vault
7. ✅ Jenkins service remains available during rotation
8. ✅ Error conditions handled gracefully

**Overall Test FAILS if:**
- ❌ Certificate not rotated automatically
- ❌ Old cert not revoked in Vault
- ❌ Service interruption during rotation
- ❌ Errors cause crash loops or secret corruption

---

## Cleanup After Testing

```bash
# 1. Reset rotation schedule to production values
cat > /tmp/cert-rotation-prod.env <<'EOF'
export VAULT_PKI_ROLE_TTL="720h"                   # 30 days
export JENKINS_CERT_ROTATOR_RENEW_BEFORE="432000"  # 5 days
export JENKINS_CERT_ROTATOR_SCHEDULE="0 */12 * * *" # Every 12 hours
EOF

# 2. If keeping Jenkins deployment, update CronJob
source /tmp/cert-rotation-prod.env
kubectl delete cronjob jenkins-cert-rotator -n jenkins
# Re-deploy Jenkins to get updated CronJob config

# 3. Or destroy test environment completely
./scripts/k3d-manager destroy_cluster
```

---

## Troubleshooting

### Issue: CronJob not running

```bash
# Check CronJob status
kubectl get cronjob jenkins-cert-rotator -n jenkins -o yaml | grep -A10 status

# Check for suspended flag
kubectl patch cronjob jenkins-cert-rotator -n jenkins -p '{"spec":{"suspend":false}}'

# Manually trigger
kubectl create job manual-test --from=cronjob/jenkins-cert-rotator -n jenkins
```

### Issue: Image pull failures

```bash
# Check pod events
kubectl get events -n jenkins --field-selector involvedObject.name=jenkins-cert-rotator-xxx

# Try alternative image
export JENKINS_CERT_ROTATOR_IMAGE="bitnami/kubectl:latest"
# Re-deploy
```

### Issue: Vault login fails

```bash
# Check Vault role exists
kubectl exec -n vault vault-0 -- \
  vault read auth/kubernetes/role/jenkins-cert-rotator

# Check ServiceAccount token
kubectl exec -n jenkins jenkins-cert-rotator-xxx-yyy -- \
  cat /var/run/secrets/kubernetes.io/serviceaccount/token
```

### Issue: Permission denied on secret update

```bash
# Verify RBAC
kubectl auth can-i get secrets --as=system:serviceaccount:jenkins:jenkins-cert-rotator -n istio-system
kubectl auth can-i create secrets --as=system:serviceaccount:jenkins:jenkins-cert-rotator -n istio-system
kubectl auth can-i patch secrets --as=system:serviceaccount:jenkins:jenkins-cert-rotator -n istio-system

# All should return "yes"
```

---

## Next Steps After Validation

Once all tests pass:

1. **Document Results**
   - Fill in test results template
   - Create GitHub issue if problems found
   - Update CLAUDE.md with any findings

2. **Update Configuration**
   - Document recommended production values
   - Add monitoring/alerting recommendations
   - Update troubleshooting guides

3. **Create Operational Runbook**
   - How to check cert expiry
   - How to force manual rotation
   - How to disable auto-rotation
   - Emergency procedures

4. **Mark Task Complete**
   - Update `docs/plans/remaining-tasks-priority.md`
   - Move to Priority 2 tasks
   - Consider merge to main branch
