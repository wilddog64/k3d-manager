#!/usr/bin/env bash
# Upload Jenkins test jobs for K8s agents

set -e

JENKINS_NAMESPACE="jenkins"
JENKINS_POD="jenkins-0"
TEST_JOBS_DIR="scripts/etc/jenkins/test-jobs"

echo "=== Uploading Jenkins test jobs ==="

# Get Jenkins admin credentials
JENKINS_USER=$(kubectl get secret -n $JENKINS_NAMESPACE jenkins-admin -o jsonpath='{.data.jenkins-admin-user}' | base64 -d)
JENKINS_PASS=$(kubectl get secret -n $JENKINS_NAMESPACE jenkins-admin -o jsonpath='{.data.jenkins-admin-password}' | base64 -d)

# Get Jenkins URL (internal cluster URL)
JENKINS_URL="http://jenkins.${JENKINS_NAMESPACE}.svc.cluster.local:8080"

echo "Creating test jobs..."

for job_file in ${TEST_JOBS_DIR}/*.groovy; do
    job_name=$(basename "$job_file" .groovy)
    echo "  - Creating job: $job_name"

    # Create job XML from Groovy pipeline
    cat > /tmp/${job_name}.xml <<EOF
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job@2.40">
  <description>Kubernetes agent test job</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps@2.90">
    <script>$(cat "$job_file")</script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
EOF

    # Upload job using Jenkins REST API via kubectl port-forward
    # Try to create, if exists (409), update instead
    response=$(kubectl exec -n $JENKINS_NAMESPACE $JENKINS_POD -c jenkins -- \
        curl -X POST -s -w "\n%{http_code}" \
        -u "${JENKINS_USER}:${JENKINS_PASS}" \
        -H "Content-Type: application/xml" \
        --data-binary "@-" \
        "${JENKINS_URL}/createItem?name=${job_name}" < /tmp/${job_name}.xml 2>/dev/null)

    http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "200" ]; then
        echo "    ✓ Job $job_name created"
    elif [ "$http_code" = "400" ]; then
        # Job already exists, update it
        kubectl exec -n $JENKINS_NAMESPACE $JENKINS_POD -c jenkins -- \
            curl -X POST -s \
            -u "${JENKINS_USER}:${JENKINS_PASS}" \
            -H "Content-Type: application/xml" \
            --data-binary "@-" \
            "${JENKINS_URL}/job/${job_name}/config.xml" < /tmp/${job_name}.xml > /dev/null 2>&1
        echo "    ✓ Job $job_name updated"
    else
        echo "    ✗ Job $job_name failed (HTTP $http_code)"
    fi
done

echo ""
echo "=== Test jobs uploaded successfully ==="
echo ""
echo "Access Jenkins UI and run the test jobs:"
echo "  1. Get Jenkins URL: kubectl get svc -n jenkins"
echo "  2. Port-forward: kubectl port-forward -n jenkins svc/jenkins 8080:8080"
echo "  3. Open: http://localhost:8080"
echo "  4. Login with admin credentials"
echo "  5. Run jobs: 01-linux-agent-test and 02-kaniko-agent-test"
