# Jenkins Kubernetes Cloud Not Applied (labels missing 'linux')

**Date:** 2026-02-27
**Status:** FIXED

## Summary

After adding the Kubernetes cloud JCasC block (02-kubernetes-agents.yaml) we reverted the
security realm to local auth in the default `values.yaml` template. However, when Jenkins
deploys in "no directory service" mode, the template now uses `values-default.yaml.tmpl`
which still embeds `${JENKINS_NAMESPACE}` placeholders. These placeholders are never expanded
because envsubst only runs for LDAP/AD templates (which have explicit `.tmpl` suffixes). In
the default path, the raw template is applied without substitution, so the generated
configmap under `casc_configs/02-kubernetes-agents.yaml.yaml` contains literal
`jenkins.${JENKINS_NAMESPACE}.svc`, etc. At runtime JCasC treats `${JENKINS_NAMESPACE}` as
an empty string, resulting in `jenkins..svc.cluster.local` in the cloud definition. The
Kubernetes plugin refuses to schedule any agent pods, so Jenkins reports "Jenkins doesn’t have
label 'linux'" for every agent job.

## Impact

- Jenkins smoke deploys without LDAP/AD cannot launch Kubernetes agents.
- The linux-agent/kaniko-agent Job DSL jobs sit in the queue with "doesn't have label" errors.
- Stage 2 release blocker: Jenkins cloud must work before `v0.1.0` release.

## Reproduction

1. `CLUSTER_PROVIDER=orbstack PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager deploy_jenkins --enable-vault`
2. Jenkins starts, smoke test passes, but `kubectl -n jenkins get pods -l jenkins-agent` shows none.
3. Jenkins logs show the linux-agent job waiting because no node matches `linux`.
4. `/var/jenkins_home/casc_configs/02-kubernetes-agents.yaml.yaml` contains `${JENKINS_NAMESPACE}`.
5. `_jenkins_run_smoke_test` sets `Jenkins.instance.clouds` (via Groovy) to
   `jenkins..svc.cluster.local`.

## Resolution

- Ensured `_deploy_jenkins` always exports the admin placeholders before running envsubst so the
  `.tmpl` path is used in *all* auth modes (default/LDAP/AD). This allows `${JENKINS_NAMESPACE}` to
  expand even when no directory service is selected.
- Re-rendered the config and confirmed the namespace is concrete:

```
$ kubectl -n jenkins get configmap jenkins-jenkins-config-02-kubernetes-agents.yaml \
    -o jsonpath='{.data.*}' | grep jenkinsUrl
        jenkinsUrl: "http://jenkins.jenkins.svc.cluster.local:8080"
```
- Reran the end-to-end validation: `PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager deploy_jenkins --enable-vault`
  followed by `PATH="/opt/homebrew/bin:$PATH" JENKINS_URL="http://127.0.0.1:8083" ./bin/run-k8s-agent-tests.sh`.
  The linux + kaniko jobs now trigger successfully and their pods progress from Pending → Running → Completed
  (`timeout 120 kubectl -n jenkins get pods -w | grep agent`). Jenkins REST API shows
  `"result":"SUCCESS"` for both jobs.

## References

- `scripts/etc/jenkins/values-default.yaml.tmpl`
- `scripts/plugins/jenkins.sh` template selection logic
- Groovy output: `CLOUD: kubernetes type=... jenkins.jenkins.svc`
- Job logs showing both linux/kaniko jobs succeeding

## References

- `scripts/etc/jenkins/values-default.yaml.tmpl`
- `scripts/plugins/jenkins.sh` template selection logic
- Groovy output: `CLOUD: kubernetes type=... jenkins..svc`
- Job logs showing "Jenkins doesn’t have label 'linux'"
