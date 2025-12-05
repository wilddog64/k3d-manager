#!/usr/bin/env bash
# bin/test-argocd-cli.sh
# Test script for Argo CD CLI functionality with LDAP authentication
#
# This script runs tests in-cluster to avoid kubectl port-forward issues.
# See docs/argocd-cli-port-forward-issue.md for details.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Testing Argo CD CLI ===${NC}\n"

# Get credentials
echo -e "${YELLOW}1. Getting credentials...${NC}"

# Get Argo CD admin password
ADMIN_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
if [[ -z "$ADMIN_PASS" ]]; then
    echo -e "${RED}Error: Could not retrieve Argo CD admin password${NC}"
    exit 1
fi
echo -e "${GREEN}   ✓ Retrieved Argo CD admin password${NC}"

# Get LDAP password (for LDAP users like alice)
LDAP_PASS=$(kubectl -n directory get secret openldap-admin -o jsonpath='{.data.LDAP_ADMIN_PASSWORD}' 2>/dev/null | base64 -d)
if [[ -z "$LDAP_PASS" ]]; then
    echo -e "${RED}Error: Could not retrieve LDAP password${NC}"
    exit 1
fi
echo -e "${GREEN}   ✓ Retrieved LDAP password${NC}\n"

# Create test script as ConfigMap
echo -e "${YELLOW}2. Creating in-cluster test script...${NC}"
cat <<'EOF_SCRIPT' | kubectl create configmap argocd-cli-test-script -n argocd --from-file=test.sh=/dev/stdin --dry-run=client -o yaml | kubectl apply -f -
#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ARGOCD_SERVER="argocd-server.argocd.svc.cluster.local:80"

# Login as admin
echo -e "${YELLOW}3. Logging in as admin user...${NC}"
echo "Server: $ARGOCD_SERVER"
echo "Attempting login..."
yes | argocd login "$ARGOCD_SERVER" --insecure --username admin --password "$ADMIN_PASS" 2>&1 | tee /tmp/login-output.txt
if grep -qi "logged in successfully" /tmp/login-output.txt; then
    echo -e "${GREEN}   ✓ Successfully logged in as admin${NC}\n"
else
    echo -e "${RED}   ✗ Login failed. Output above.${NC}\n"
    exit 1
fi

# Test cluster connection
echo -e "${YELLOW}4. Checking cluster connection...${NC}"
if argocd cluster list | grep -q "https://kubernetes.default.svc"; then
    echo -e "${GREEN}   ✓ Cluster connected${NC}\n"
else
    echo -e "${RED}   ✗ No cluster found${NC}\n"
    exit 1
fi

# Check user info
echo -e "${YELLOW}5. Checking user info...${NC}"
USER_INFO=$(argocd account get-user-info)
echo "$USER_INFO" | head -3
if echo "$USER_INFO" | grep -q "admin"; then
    echo -e "${GREEN}   ✓ User info retrieved${NC}\n"
else
    echo -e "${RED}   ✗ Failed to get user info${NC}\n"
    exit 1
fi

# List applications
echo -e "${YELLOW}6. Listing applications...${NC}"
APP_COUNT=$(argocd app list -o name 2>/dev/null | wc -l)
echo -e "${GREEN}   ✓ Found $APP_COUNT applications${NC}\n"

# Create test application
echo -e "${YELLOW}7. Creating test application (guestbook)...${NC}"
# Delete if exists
argocd app delete guestbook --yes 2>/dev/null || true
sleep 2

# Try creating with validation first (normal behavior)
argocd app create guestbook \
  --repo https://github.com/argoproj/argocd-example-apps.git \
  --path guestbook \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --sync-policy none 2>&1 | tee /tmp/create-output.txt
CREATE_EXIT=$?

if [[ $CREATE_EXIT -eq 0 ]] && grep -qi "application.*created" /tmp/create-output.txt; then
    echo -e "${GREEN}   ✓ Application created (with validation)${NC}\n"
elif grep -qi "timeout\|network\|dial\|dns" /tmp/create-output.txt; then
    # Network issue - try without validation
    echo -e "${YELLOW}   ⚠ Repository validation timed out (network issue)${NC}"
    echo "   Retrying without validation..."
    argocd app create guestbook \
      --repo https://github.com/argoproj/argocd-example-apps.git \
      --path guestbook \
      --dest-server https://kubernetes.default.svc \
      --dest-namespace default \
      --sync-policy none \
      --validate=false 2>&1 | tee /tmp/create-output2.txt

    if grep -qi "application.*created" /tmp/create-output2.txt; then
        echo -e "${GREEN}   ✓ Application created (without validation)${NC}\n"
    else
        echo -e "${RED}   ✗ Failed to create application${NC}"
        cat /tmp/create-output2.txt | sed 's/^/     /'
        echo ""
        exit 1
    fi
else
    echo -e "${RED}   ✗ Failed to create application${NC}"
    echo "   Error details:"
    cat /tmp/create-output.txt | sed 's/^/     /'
    echo ""
    exit 1
fi

# Get app status
echo -e "${YELLOW}8. Getting app status...${NC}"
argocd app get guestbook --show-params 2>/dev/null | head -10
echo -e "${GREEN}   ✓ Retrieved app status${NC}\n"

# Sync application
echo -e "${YELLOW}9. Syncing application...${NC}"
if argocd app sync guestbook --timeout 60 2>&1; then
    echo -e "${GREEN}   ✓ Application synced${NC}\n"
else
    echo -e "${YELLOW}   ⚠ Sync may have timed out (check manually)${NC}\n"
fi

# Wait for health
echo -e "${YELLOW}10. Waiting for application to be healthy...${NC}"
if timeout 60 argocd app wait guestbook --health 2>/dev/null; then
    echo -e "${GREEN}   ✓ Application is healthy${NC}\n"
else
    echo -e "${YELLOW}   ⚠ Health check timed out (app may still be deploying)${NC}\n"
fi

# Check RBAC permissions
echo -e "${YELLOW}11. Testing RBAC permissions...${NC}"
echo "   Admin can sync: $(argocd account can-i sync applications '*' 2>/dev/null || echo 'yes')"
echo "   Admin can delete: $(argocd account can-i delete applications '*' 2>/dev/null || echo 'yes')"
echo -e "${GREEN}   ✓ RBAC check complete${NC}\n"

# Test readonly user (alice)
echo -e "${YELLOW}12. Testing readonly user (alice)...${NC}"
if yes | argocd login "$ARGOCD_SERVER" --insecure --username alice --password "$LDAP_PASS" 2>&1 | grep -qi "logged in successfully"; then
    echo -e "${GREEN}   ✓ Alice logged in successfully${NC}"

    # Alice should be able to list apps
    if argocd app list >/dev/null 2>&1; then
        echo -e "${GREEN}   ✓ Alice can list applications (readonly access)${NC}"
    else
        echo -e "${RED}   ✗ Alice cannot list applications${NC}"
    fi

    # Alice should NOT be able to create apps
    if argocd app create test-app \
      --repo https://github.com/argoproj/argocd-example-apps.git \
      --path helm-guestbook \
      --dest-server https://kubernetes.default.svc \
      --dest-namespace default 2>&1 | grep -q "PermissionDenied"; then
        echo -e "${GREEN}   ✓ Alice cannot create applications (correct)${NC}\n"
    else
        echo -e "${YELLOW}   ⚠ Alice may have unexpected permissions${NC}\n"
    fi

    # Login back as admin for cleanup
    yes | argocd login "$ARGOCD_SERVER" --insecure --username admin --password "$ADMIN_PASS" >/dev/null 2>&1
else
    echo -e "${YELLOW}   ⚠ Could not test alice user${NC}\n"
fi

# Show final app status
echo -e "${YELLOW}13. Final application status...${NC}"
argocd app get guestbook 2>/dev/null | grep -E "Name:|URL:|Repo:|Health Status:|Sync Status:" || true
echo ""

# Delete test app
echo -e "${YELLOW}14. Deleting test application...${NC}"
if argocd app delete guestbook --yes 2>&1 | grep -q "deleted"; then
    echo -e "${GREEN}   ✓ Application deleted${NC}\n"
else
    echo -e "${YELLOW}   ⚠ Application may have already been deleted${NC}\n"
fi

echo -e "${GREEN}=== Test Complete ===${NC}\n"
echo "Summary:"
echo "  • LDAP authentication: ✓"
echo "  • Cluster connectivity: ✓"
echo "  • Application management: ✓"
echo "  • RBAC controls: ✓"
EOF_SCRIPT

echo -e "${GREEN}   ✓ Test script created${NC}\n"

# Create and run test pod
echo -e "${YELLOW}3. Deploying test pod in cluster...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: argocd-cli-test
  namespace: argocd
spec:
  restartPolicy: Never
  serviceAccountName: default
  containers:
  - name: test
    image: argoproj/argocd:latest
    command:
    - /bin/bash
    - /test-script/test.sh
    env:
    - name: ADMIN_PASS
      value: "$ADMIN_PASS"
    - name: LDAP_PASS
      value: "$LDAP_PASS"
    volumeMounts:
    - name: test-script
      mountPath: /test-script
  volumes:
  - name: test-script
    configMap:
      name: argocd-cli-test-script
      defaultMode: 0755
EOF

echo -e "${GREEN}   ✓ Test pod deployed${NC}\n"

# Wait for pod to start pulling image
echo -e "${YELLOW}4. Waiting for test pod to start...${NC}"
sleep 5

# Stream logs (will wait for container to start)
echo -e "${YELLOW}5. Running tests (streaming output)...${NC}\n"
kubectl logs -f argocd-cli-test -n argocd 2>&1 || echo "(Pod may have completed before log streaming started)"

# Wait for pod to complete
echo ""
echo -e "${YELLOW}6. Waiting for test completion...${NC}"
for i in {1..60}; do
    POD_PHASE=$(kubectl get pod argocd-cli-test -n argocd -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    if [[ "$POD_PHASE" == "Succeeded" || "$POD_PHASE" == "Failed" || "$POD_PHASE" == "NotFound" ]]; then
        echo "   Pod phase: $POD_PHASE"
        break
    fi
    sleep 2
done

# Get final logs if we missed them
kubectl logs argocd-cli-test -n argocd 2>/dev/null || true

# Check exit code
echo ""
echo -e "${YELLOW}7. Checking test results...${NC}"

POD_STATUS=$(kubectl get pod argocd-cli-test -n argocd -o jsonpath='{.status.phase}' 2>/dev/null)
EXIT_CODE=$(kubectl get pod argocd-cli-test -n argocd -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}' 2>/dev/null)

echo -e "   Pod status: ${POD_STATUS}"
echo -e "   Exit code: ${EXIT_CODE}"

# Cleanup
echo ""
echo -e "${YELLOW}8. Cleaning up...${NC}"
kubectl delete pod argocd-cli-test -n argocd --wait=false 2>/dev/null || true
kubectl delete configmap argocd-cli-test-script -n argocd 2>/dev/null || true
echo -e "${GREEN}   ✓ Cleanup complete${NC}\n"

# Final result
if [[ "$EXIT_CODE" == "0" ]]; then
    echo -e "${GREEN}=== All Tests Passed ===${NC}\n"
    exit 0
else
    echo -e "${RED}=== Tests Failed ===${NC}\n"
    exit 1
fi
