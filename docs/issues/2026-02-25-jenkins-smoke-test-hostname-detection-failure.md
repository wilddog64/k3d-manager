# Jenkins Smoke Test Hostname Detection Failure

**Date:** 2026-02-25
**Status:** Fixed

## Description

In `scripts/plugins/jenkins.sh`, the `_jenkins_run_smoke_test` function fails to automatically detect the Jenkins hostname from the Istio VirtualService, resulting in a fallback warning:
`WARN: [jenkins] could not detect Jenkins hostname from VirtualService, using default: jenkins.dev.local.me`

### Root Cause

The script attempts to retrieve the VirtualService from the `istio-system` namespace:

```bash
jenkins_host=$(kubectl -n istio-system get vs jenkins -o jsonpath='{.spec.hosts[0]}' 2>/dev/null || echo "")
```

However, the `jenkins` VirtualService is deployed to the `jenkins` namespace (or whatever namespace is passed to the function), not `istio-system`.

## Impact

- The smoke test relies on a hardcoded default (`jenkins.dev.local.me`) if the detection fails.
- If a user deploys Jenkins with a custom hostname, the smoke test will target the wrong host and likely fail TLS verification or connectivity.

## Confirmed Root Cause (2026-02-25)

Verified by reading `scripts/etc/jenkins/virtualservice.yaml.tmpl` — the VirtualService
is deployed to `${JENKINS_NAMESPACE}`, not `istio-system`. The lookup on line 913 of
`scripts/plugins/jenkins.sh` always fails, always falls back to the hardcoded default,
and always produces the WARN.

## Resolution (2026-02-25)

- `_jenkins_run_smoke_test` now queries the Jenkins VirtualService in the same namespace
  that was passed into the function (`kubectl -n "$namespace" get vs jenkins ...`).
- The fallback to `${VAULT_PKI_LEAF_HOST:-jenkins.dev.local.me}` remains as a guardrail,
  so clusters without the VirtualService still log a WARN but continue.
- Manual verification: `CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_jenkins --enable-vault`
  no longer emits the "could not detect Jenkins hostname" warning when Jenkins is
  deployed with a custom host.
