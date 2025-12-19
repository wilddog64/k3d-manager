# Manual Job Creation for K8s Agent Testing

Since Jenkins is configured with LDAP authentication, we need to create the test jobs manually through the UI.

## Step 1: Access Jenkins
Open: https://jenkins.dev.local.me

## Step 2: Create Test Job #1

1. Click "New Item"
2. Enter name: `01-linux-agent-test`
3. Select: "Pipeline"
4. Click "OK"
5. Scroll down to "Pipeline" section
6. In the "Script" text area, paste the following:

```groovy
$(cat scripts/etc/jenkins/test-jobs/01-linux-agent-test.groovy)
```

7. Click "Save"

## Step 3: Create Test Job #2

1. Click "New Item"  
2. Enter name: `02-kaniko-agent-test`
3. Select: "Pipeline"
4. Click "OK"
5. Scroll down to "Pipeline" section
6. In the "Script" text area, paste the following:

```groovy
$(cat scripts/etc/jenkins/test-jobs/02-kaniko-agent-test.groovy)
```

7. Click "Save"

## Step 4: Run the Tests

1. Go to Dashboard
2. Click "01-linux-agent-test" → "Build Now"
3. Click on the build number → "Console Output"
4. Watch the agent pod being created and the test running
5. Repeat for "02-kaniko-agent-test"

## Step 5: Monitor Agent Pods

In terminal:
```bash
kubectl get pods -n jenkins -w
```

You should see pods like `linux-agent-xxxxx` and `kaniko-agent-xxxxx` being created and deleted automatically.
