# Jenkins k8s agents fail with `serviceaccount "jenkins-admin" not found`

**Date:** 2026-02-27
**Status:** FIXED

## Summary

Jenkins Kubernetes agent pods never started because the default Helm values forced the pod
templates (and RBAC) to use a `jenkins-admin` ServiceAccount. The upstream chart only creates the
built-in `jenkins` ServiceAccount, so scheduler events showed repeated failures:

```
Warning  FailedCreate  pod/linux-agent-6n9xk   Error creating: serviceaccount "jenkins-admin" not found
```

Because the Jenkins controller never created agents, every linux/kaniko job stayed queued with
"Jenkins doesn't have label 'linux'".

## Impact

- All Jenkins jobs that require the `linux` or `kaniko` labels stay queued.
- Stage 2 sign-off blocked: we cannot prove k8s agent support end-to-end.

## Root Cause

- `scripts/etc/jenkins/values-*.yaml.tmpl` overrides `controller.serviceAccount.name` to
  `jenkins-admin`, but no manifest creates that ServiceAccount.
- The `02-kubernetes-agents` JCasC templates and `agent-rbac.yaml.tmpl` also referenced
  `jenkins-admin`, so every dynamic pod launch failed immediately.

## Fix

- Switch the controller back to the stock `jenkins` ServiceAccount and keep `create: true` so the
  Helm chart manages it.
- Update every agent pod template and the RBAC RoleBinding to reference the same `jenkins`
  ServiceAccount.

Files touched:
- `scripts/etc/jenkins/values-default.yaml.tmpl`
- `scripts/etc/jenkins/values-ldap.yaml.tmpl`
- `scripts/etc/jenkins/values-ad-test.yaml.tmpl`
- `scripts/etc/jenkins/values-ad-prod.yaml.tmpl`
- `scripts/etc/jenkins/agent-rbac.yaml.tmpl`

## Validation

1. `CLUSTER_PROVIDER=orbstack PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager deploy_jenkins --enable-vault`
2. `PATH="/opt/homebrew/bin:$PATH" JENKINS_URL="http://127.0.0.1:8083" ./bin/run-k8s-agent-tests.sh`
3. `timeout 120 kubectl -n jenkins get pods -w | grep agent` → linux + kaniko pods schedule, run, and terminate cleanly.
4. `curl -sk -u jenkins-admin:*** http://127.0.0.1:8083/job/01-linux-agent-test/lastBuild/api/json | jq '.result'` → `"SUCCESS"`

Both jobs now complete, proving the corrected ServiceAccount wiring.

## Follow-up

- After the next Jenkins deploy, grab the controller logs to ensure the Kubernetes plugin reports a
  healthy cloud (no more SA errors).
- Consider adding a preflight that validates the ServiceAccount before Helm upgrade.
