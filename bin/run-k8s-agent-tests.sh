#!/usr/bin/env bash
# Trigger Jenkins K8s agent test jobs

set -e

JENKINS_NAMESPACE="${JENKINS_NAMESPACE:-jenkins}"
JENKINS_URL="${JENKINS_URL:-https://jenkins.dev.local.me}"

echo "=== Triggering Jenkins K8s Agent Tests ==="
echo ""

# Get Jenkins admin credentials
JENKINS_USER=$(kubectl get secret -n "$JENKINS_NAMESPACE" jenkins-admin -o jsonpath='{.data.jenkins-admin-user}' | base64 -d)
JENKINS_PASS=$(kubectl get secret -n "$JENKINS_NAMESPACE" jenkins-admin -o jsonpath='{.data.jenkins-admin-password}' | base64 -d)

# Get Jenkins crumb for CSRF protection
echo "Getting Jenkins crumb..."
CRUMB=$(curl -s -u "${JENKINS_USER}:${JENKINS_PASS}" \
    "${JENKINS_URL}/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)" \
    --insecure 2>/dev/null)

if [ -z "$CRUMB" ] || [[ "$CRUMB" == *"401"* ]] || [[ "$CRUMB" == *"html"* ]]; then
    echo "Warning: Could not get Jenkins crumb (LDAP auth issue)"
    echo "You'll need to trigger builds manually through the UI or use an API token"
    echo ""
    echo "To run tests manually:"
    echo "  1. Open: $JENKINS_URL"
    echo "  2. Login with your LDAP credentials"
    echo "  3. Click on '01-linux-agent-test' → 'Build Now'"
    echo "  4. Click on '02-kaniko-agent-test' → 'Build Now'"
    echo "  5. Monitor pods: kubectl get pods -n $JENKINS_NAMESPACE -w"
    exit 1
fi

CRUMB_FIELD="${CRUMB%%:*}"
CRUMB_VALUE="${CRUMB##*:}"

echo "Got crumb: $CRUMB_FIELD"
echo ""

# Trigger test jobs
for job in "01-linux-agent-test" "02-kaniko-agent-test"; do
    echo "Triggering job: $job"

    response=$(curl -X POST -s -w "\n%{http_code}" \
        -u "${JENKINS_USER}:${JENKINS_PASS}" \
        -H "$CRUMB_FIELD: $CRUMB_VALUE" \
        "${JENKINS_URL}/job/${job}/build" \
        --insecure 2>&1)

    http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "201" ]; then
        echo "  ✓ Job '$job' triggered successfully"
    else
        echo "  ✗ Failed to trigger job (HTTP $http_code)"
        if [[ "$response" == *"401"* ]]; then
            echo "  Note: 401 Unauthorized - LDAP authentication required"
        fi
    fi
    echo ""
done

echo "=== Monitor Agent Pods ==="
echo "Run: kubectl get pods -n $JENKINS_NAMESPACE -w"
echo ""
echo "Or check Jenkins UI: $JENKINS_URL"
