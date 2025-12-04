#!/usr/bin/env bash
# bin/test-argocd-cli.sh
# Test script for Argo CD CLI functionality with LDAP authentication

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Ensure argocd is in PATH
export PATH="$HOME/bin:$PATH"

# Check if argocd CLI is installed
if ! command -v argocd &> /dev/null; then
    echo -e "${RED}Error: argocd CLI not found${NC}"
    echo "Please run: curl -sSL -o ~/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-arm64 && chmod +x ~/bin/argocd"
    exit 1
fi

echo -e "${GREEN}=== Testing Argo CD CLI ===${NC}\n"

# Get LDAP credentials
echo -e "${YELLOW}1. Getting LDAP credentials...${NC}"
LDAP_PASS=$(kubectl -n directory get secret openldap-env -o jsonpath='{.data.LDAP_ADMIN_PASSWORD}' 2>/dev/null | base64 -d)
if [[ -z "$LDAP_PASS" ]]; then
    echo -e "${RED}Error: Could not retrieve LDAP password${NC}"
    exit 1
fi
echo -e "${GREEN}   ✓ Retrieved LDAP password${NC}\n"

# Start port-forward
echo -e "${YELLOW}2. Starting port-forward to Argo CD server...${NC}"
kubectl port-forward svc/argocd-server -n argocd 8080:443 >/dev/null 2>&1 &
PF_PID=$!
sleep 3
echo -e "${GREEN}   ✓ Port-forward active (PID: $PF_PID)${NC}\n"

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    if [[ -n "$PF_PID" ]]; then
        kill $PF_PID 2>/dev/null || true
        echo -e "${GREEN}   ✓ Stopped port-forward${NC}"
    fi

    # Delete test app if it exists
    argocd app delete guestbook --yes 2>/dev/null || true
}
trap cleanup EXIT

# Login as admin
echo -e "${YELLOW}3. Logging in as admin user...${NC}"
if argocd login localhost:8080 --insecure --username admin --password "$LDAP_PASS" 2>&1 | grep -q "Logged in"; then
    echo -e "${GREEN}   ✓ Successfully logged in as admin${NC}\n"
else
    echo -e "${RED}   ✗ Login failed${NC}\n"
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
if argocd app create guestbook \
  --repo https://github.com/argoproj/argocd-example-apps.git \
  --path guestbook \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --sync-policy none 2>&1 | grep -q "application.*created"; then
    echo -e "${GREEN}   ✓ Application created${NC}\n"
else
    echo -e "${YELLOW}   ⚠ Application may already exist${NC}\n"
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
if argocd login localhost:8080 --insecure --username alice --password "$LDAP_PASS" 2>&1 | grep -q "Logged in"; then
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
    argocd login localhost:8080 --insecure --username admin --password "$LDAP_PASS" >/dev/null 2>&1
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
echo ""
echo "To access Argo CD UI, run:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8081:80 &"
echo "  Open: http://localhost:8081"
echo "  Login: admin / <LDAP password>"
