#!/usr/bin/env bash
# Quick-start script for certificate rotation testing on Ubuntu/k3s
# Usage: ./scripts/tests/run-cert-rotation-test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "==================================================================="
echo "Certificate Rotation Validation Test - Quick Start"
echo "==================================================================="
echo ""
echo "This script will:"
echo "  1. Create test configuration for short-lived certificates"
echo "  2. Deploy k3s cluster (if needed)"
echo "  3. Deploy Jenkins with Vault"
echo "  4. Guide you through the test validation steps"
echo ""
echo "Prerequisites:"
echo "  - Ubuntu Linux with systemd"
echo "  - sudo access (for k3s installation)"
echo "  - ~30 minutes total time (~15 min active)"
echo ""
read -p "Ready to proceed? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Step 1: Create test configuration
echo ""
echo "==================================================================="
echo "Step 1: Creating test configuration"
echo "==================================================================="

cat > /tmp/cert-rotation-test.env <<'EOF'
# Short-lived certificates for rapid testing
export VAULT_PKI_ROLE_TTL="10m"                    # Certificate lifetime: 10 minutes
export JENKINS_CERT_ROTATOR_RENEW_BEFORE="300"     # Renew when 5 min remaining (300 sec)
export JENKINS_CERT_ROTATOR_SCHEDULE="*/2 * * * *" # CronJob checks every 2 minutes
export JENKINS_CERT_ROTATOR_ENABLED="1"            # Enable rotation
export JENKINS_CERT_ROTATOR_IMAGE="docker.io/google/cloud-sdk:slim"
EOF

source /tmp/cert-rotation-test.env

echo "✅ Test configuration created at: /tmp/cert-rotation-test.env"
echo ""
echo "Configuration:"
echo "  - Cert lifetime: 10 minutes"
echo "  - Renewal threshold: 5 minutes"
echo "  - Check interval: 2 minutes"
echo ""

# Step 2: Check/Deploy k3s cluster
echo "==================================================================="
echo "Step 2: Checking k3s cluster"
echo "==================================================================="

if kubectl cluster-info &>/dev/null; then
    echo "✅ Kubernetes cluster is accessible"
    kubectl cluster-info | head -3
else
    echo "⚠️  No cluster detected. Deploying k3s cluster..."
    echo ""
    export CLUSTER_PROVIDER=k3s
    cd "$REPO_ROOT"
    ./scripts/k3d-manager deploy_cluster -f
fi

echo ""

# Step 3: Deploy Jenkins
echo "==================================================================="
echo "Step 3: Deploying Jenkins with Vault"
echo "==================================================================="
echo ""
echo "This will take 5-7 minutes..."
echo ""

cd "$REPO_ROOT"
source /tmp/cert-rotation-test.env
./scripts/k3d-manager deploy_jenkins --enable-vault

echo ""
echo "✅ Jenkins deployed successfully"
echo ""

# Step 4: Capture initial certificate
echo "==================================================================="
echo "Step 4: Capturing initial certificate information"
echo "==================================================================="

INITIAL_SERIAL=$(kubectl get secret jenkins-tls -n istio-system \
  -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d | \
  openssl x509 -noout -serial 2>/dev/null | cut -d= -f2)

if [[ -z "$INITIAL_SERIAL" ]]; then
    echo "❌ ERROR: Could not find jenkins-tls secret"
    echo "Check deployment logs above for errors"
    exit 1
fi

echo "Initial certificate serial: $INITIAL_SERIAL"
echo ""

echo "Certificate details:"
kubectl get secret jenkins-tls -n istio-system \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | \
  openssl x509 -noout -subject -dates

echo ""
echo "Saving serial to /tmp/initial-cert-serial.txt"
echo "$INITIAL_SERIAL" > /tmp/initial-cert-serial.txt

# Step 5: Verify CronJob
echo ""
echo "==================================================================="
echo "Step 5: Verifying CronJob deployment"
echo "==================================================================="

kubectl get cronjob jenkins-cert-rotator -n jenkins

echo ""
echo "✅ CronJob deployed with schedule: */2 * * * *"

# Step 6: Manual test
echo ""
echo "==================================================================="
echo "Step 6: Running manual rotation test"
echo "==================================================================="

kubectl create job manual-cert-test --from=cronjob/jenkins-cert-rotator -n jenkins

echo ""
echo "Waiting for job to complete..."
sleep 5

kubectl logs -n jenkins job/manual-cert-test -f 2>/dev/null || true

echo ""
echo "Job status:"
kubectl get job manual-cert-test -n jenkins

echo ""
echo "✅ Manual test completed"
echo "   (Should show: 'Certificate is valid, skipping rotation')"

# Step 7: Instructions for monitoring rotation
echo ""
echo "==================================================================="
echo "Step 7: Monitoring automatic rotation"
echo "==================================================================="
echo ""
echo "The certificate will rotate in approximately 5-7 minutes."
echo ""
echo "Timeline:"
echo "  T+0:  Certificate issued (valid for 10 min)"
echo "  T+5:  Rotation window opens (5 min remaining)"
echo "  T+6:  Next CronJob run detects expiring cert"
echo "  T+7:  Certificate rotated"
echo ""
echo "To monitor rotation, run these commands in separate terminals:"
echo ""
echo "Terminal 1 - Watch CronJob executions:"
echo "  watch -n 10 'kubectl get jobs -n jenkins --sort-by=.metadata.creationTimestamp | tail -5'"
echo ""
echo "Terminal 2 - Watch for new rotation job:"
echo "  kubectl get jobs -n jenkins -w"
echo ""
echo "When a new job appears (after ~6 minutes), check its logs:"
echo "  kubectl logs -n jenkins job/jenkins-cert-rotator-<timestamp> -f"
echo ""
echo "Expected log output when rotation occurs:"
echo "  [INFO] Certificate expires in XXs (threshold 300s); rotating"
echo "  [INFO] Updated TLS secret istio-system/jenkins-tls"
echo ""
echo "==================================================================="
echo "After rotation completes, verify with:"
echo "==================================================================="
echo ""
cat <<'VERIFY_SCRIPT'
# Get new certificate serial
NEW_SERIAL=$(kubectl get secret jenkins-tls -n istio-system \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | \
  openssl x509 -noout -serial | cut -d= -f2)

INITIAL_SERIAL=$(cat /tmp/initial-cert-serial.txt)

echo "Initial serial: $INITIAL_SERIAL"
echo "New serial:     $NEW_SERIAL"

if [ "$INITIAL_SERIAL" != "$NEW_SERIAL" ]; then
  echo "✅ SUCCESS: Certificate rotated!"
else
  echo "❌ FAIL: Certificate not rotated"
fi

# Check if old cert was revoked in Vault
OLD_SERIAL_NORM=$(echo $INITIAL_SERIAL | tr -d ':' | tr '[:lower:]' '[:upper:]')
echo ""
echo "Checking Vault for revoked certificate..."
kubectl exec -n vault vault-0 -- vault list pki/certs/revoked | grep -i "$OLD_SERIAL_NORM" \
  && echo "✅ Old certificate revoked in Vault" \
  || echo "⚠️  Old certificate not found in revoked list"
VERIFY_SCRIPT

echo ""
echo "==================================================================="
echo "Test Plan: docs/tests/certificate-rotation-validation.md"
echo "==================================================================="
echo ""
echo "For detailed validation steps, see:"
echo "  ${REPO_ROOT}/docs/tests/certificate-rotation-validation.md"
echo ""
echo "Good luck! 🎯"
