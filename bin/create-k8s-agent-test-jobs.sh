#!/usr/bin/env bash
# Create Jenkins test jobs for K8s agents using REST API

set -e

JENKINS_NAMESPACE="${JENKINS_NAMESPACE:-jenkins}"
JENKINS_URL="${JENKINS_URL:-https://jenkins.dev.local.me}"
TEST_JOBS_DIR="scripts/etc/jenkins/test-jobs"

echo "=== Creating Jenkins K8s Agent Test Jobs ==="

# Get Jenkins admin credentials
JENKINS_USER=$(kubectl get secret -n "$JENKINS_NAMESPACE" jenkins-admin -o jsonpath='{.data.jenkins-admin-user}' | base64 -d)
JENKINS_PASS=$(kubectl get secret -n "$JENKINS_NAMESPACE" jenkins-admin -o jsonpath='{.data.jenkins-admin-password}' | base64 -d)

echo "Jenkins URL: $JENKINS_URL"
echo "Credentials: ${JENKINS_USER}:***"
echo ""

echo "Getting Jenkins crumb..."
COOKIE_JAR=$(mktemp -t jenkins-create-jobs.XXXXXX)
trap 'rm -f "$COOKIE_JAR"' EXIT

CRUMB_JSON=$(curl -s -u "${JENKINS_USER}:${JENKINS_PASS}" \
    -c "$COOKIE_JAR" \
    "${JENKINS_URL}/crumbIssuer/api/json" \
    --insecure 2>/dev/null || true)

CRUMB_FIELD=""
CRUMB_VALUE=""
if [[ -n "$CRUMB_JSON" ]] && command -v python3 >/dev/null 2>&1; then
    if CRUMB_PAIR=$(CRUMB_JSON="$CRUMB_JSON" python3 -c 'import json, os, sys
payload = os.environ.get("CRUMB_JSON", "")
try:
    data = json.loads(payload)
    field = data.get("crumbRequestField", "")
    crumb = data.get("crumb", "")
    sys.stdout.write(f"{field}\t{crumb}")
except Exception:
    pass' 2>/dev/null); then
        IFS=$'\t' read -r CRUMB_FIELD CRUMB_VALUE <<<"${CRUMB_PAIR}" || true
    fi
fi

CRUMB_HEADER_ARGS=()
if [[ -n "$CRUMB_FIELD" ]] && [[ -n "$CRUMB_VALUE" ]]; then
    CRUMB_HEADER_ARGS=(-H "$CRUMB_FIELD: $CRUMB_VALUE")
fi

if [[ -z "$CRUMB_FIELD" ]] || [[ -z "$CRUMB_VALUE" ]]; then
    echo "Warning: Could not get Jenkins crumb, trying without it..."
else
    echo "Got crumb: $CRUMB_FIELD"
fi
echo ""

for job_file in ${TEST_JOBS_DIR}/*.groovy; do
    job_name=$(basename "$job_file" .groovy)
    echo "Creating job: $job_name"

    # Create job XML from Groovy pipeline
    cat > /tmp/${job_name}.xml <<EOF
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>Kubernetes agent test job - ${job_name}</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script><![CDATA[$(cat "$job_file")]]></script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
EOF

    # Try to create the job
    response=$(curl -X POST -s -w "\n%{http_code}" \
        -u "${JENKINS_USER}:${JENKINS_PASS}" \
        -b "$COOKIE_JAR" \
        "${CRUMB_HEADER_ARGS[@]}" \
        -H "Content-Type: application/xml" \
        --data-binary "@/tmp/${job_name}.xml" \
        "${JENKINS_URL}/createItem?name=${job_name}" \
        --insecure 2>&1)

    http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "200" ]; then
        echo "  ✓ Job '$job_name' created successfully"
    elif [ "$http_code" = "400" ]; then
        # Job already exists, try to update it
        echo "  - Job already exists, updating..."
        update_response=$(curl -X POST -s -w "\n%{http_code}" \
            -u "${JENKINS_USER}:${JENKINS_PASS}" \
            -b "$COOKIE_JAR" \
            "${CRUMB_HEADER_ARGS[@]}" \
            -H "Content-Type: application/xml" \
            --data-binary "@/tmp/${job_name}.xml" \
            "${JENKINS_URL}/job/${job_name}/config.xml" \
            --insecure 2>&1)

        update_code=$(echo "$update_response" | tail -n1)
        if [ "$update_code" = "200" ]; then
            echo "Job '$job_name' updated successfully"
        else
            echo "Failed to update job (HTTP $update_code)"
        fi
    else
        echo "  ✗ Failed to create job (HTTP $http_code)"
        echo "Response: $(echo "$response" | head -n-1)"
    fi

    # Clean up temp file
    rm -f /tmp/${job_name}.xml
    echo ""
done

echo "=== Done ==="
echo ""
echo "Next steps:"
echo "  1. Open Jenkins UI: $JENKINS_URL"
echo "  2. Login with admin credentials"
echo "  3. Run jobs: 01-linux-agent-test and 02-kaniko-agent-test"
echo ""
echo "Monitor agent pods:"
echo "  kubectl get pods -n $JENKINS_NAMESPACE -w"
