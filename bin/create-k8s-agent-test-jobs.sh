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

# Get Jenkins crumb for CSRF protection
echo "Getting Jenkins crumb..."
CRUMB=$(curl -s -u "${JENKINS_USER}:${JENKINS_PASS}" \
    "${JENKINS_URL}/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)" \
    --insecure)

if [ -z "$CRUMB" ]; then
    echo "Warning: Could not get Jenkins crumb, trying without it..."
    CRUMB_HEADER=""
else
    echo "Got crumb: ${CRUMB%%:*}"
    CRUMB_HEADER="-H $CRUMB"
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
        ${CRUMB_HEADER} \
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
            ${CRUMB_HEADER} \
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
