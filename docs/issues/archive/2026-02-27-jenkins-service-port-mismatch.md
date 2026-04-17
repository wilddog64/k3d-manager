# Jenkins Kubernetes agents can't reach controller (service port mismatch)

**Date:** 2026-02-27
**Status:** FIXED

## Summary

Our Helm values exposed the Jenkins controller Service on port 8081 (`controller.servicePort: 8081`) even
though every in-cluster reference (JCasC `jenkinsUrl`, agent templates, smoke tests, DSL jobs) targets
`http://jenkins.${JENKINS_NAMESPACE}.svc.cluster.local:8080`. Kubernetes services do not listen on the
pod's target port unless that port is explicitly exposed, so agent pods attempted to hit
`jenkins:8080` and timed out forever while Jenkins reported "All nodes of label 'linux' are offline".

Linux agent pod logs showed repeated connection failures:

```
java.io.IOException: Failed to connect to http://jenkins.jenkins.svc.cluster.local:8080/tcpSlaveAgentListener/: Connect timed out
    at org.jenkinsci.remoting.engine.JnlpAgentEndpointResolver.resolve(...)
```

## Impact

- `01-linux-agent-test` and `02-kaniko-agent-test` jobs never progressed past the queue.
- Jenkins continuously spawned pods that sat idle until they timed out.
- The release gating checklist ("linux/kaniko jobs must pass") could not be satisfied.

## Fix

- Set `controller.servicePort: 8080` in every Helm values template, matching the container/target port.
- Redeployed `deploy_jenkins --enable-vault` so the `jenkins` Service now exposes 8080/TCP.
- Re-ran `bin/create-k8s-agent-test-jobs.sh` and `bin/run-k8s-agent-tests.sh` — both jobs now finish successfully.

## Evidence

```
$ kubectl -n jenkins get svc jenkins -o jsonpath='{.spec.ports}'
[{"name":"http","port":8080,"protocol":"TCP","targetPort":8080}]

$ PATH="/opt/homebrew/bin:$PATH" JENKINS_URL="http://127.0.0.1:8083" ./bin/run-k8s-agent-tests.sh
Triggering job: 01-linux-agent-test
  ✓ Job '01-linux-agent-test' triggered successfully
Triggering job: 02-kaniko-agent-test
  ✓ Job '02-kaniko-agent-test' triggered successfully

$ curl -s -u jenkins-admin:*** -k http://127.0.0.1:8083/job/01-linux-agent-test/lastBuild/api/json | jq '.result'
"SUCCESS"
```

See also `kubectl get pods -n jenkins -w` excerpt in memory-bank update showing linux/kaniko pods
spin up and complete.

## Follow-up

- Keep `jenkinsUrl` and `controller.servicePort` in sync whenever we adjust the controller listener.
- Consider adding a smoke-test assertion that `kubectl -n jenkins port-forward svc/jenkins 8080:8080`
  succeeds before attempting to run the agent validation.
