# Jenkins Smoke Test Routing Failure on macOS

**Date:** 2026-02-24
**Status:** Fixed

## Description

The recently implemented port-forwarding logic for Jenkins smoke tests on macOS fails because it attempts to port-forward to a non-existent port on the Jenkins service.

### Error Observed
```
INFO: [jenkins] ingress IP 172.18.0.3 is private; using kubectl port-forward to 127.0.0.1:8443
WARN: [jenkins] smoke test failed; inspect output above
```

Manual investigation revealed that the `kubectl port-forward` command being executed in the background fails with:
`error: Service jenkins does not have a service port 443`

The `jenkins` service in the `jenkins` namespace only exposes port `8081`. The script attempts to tunnel `8443:443` to `svc/jenkins`, which is invalid.

## Root Cause

In `scripts/plugins/jenkins.sh`, the `_jenkins_run_smoke_test` function attempts to port-forward to the Jenkins service itself:

```bash
kubectl -n "$namespace" port-forward svc/jenkins "${pf_port}:443" >"$log_target" 2>&1 &
```

However:
1. The `jenkins` service does not have port 443 (it has 8081).
2. The intended target for SSL testing is the Istio Ingress Gateway, which *does* listen on 443 and terminates TLS for the Jenkins hostname.

## Verified Fixes (Successful)

While the smoke test routing failed, the following fixes were successfully verified:

1.  **Vault macOS `mkdir` Fix**: `deploy_vault` no longer attempts to create host-side directories for `local-path` PVs on macOS.
2.  **Jenkins JCasC `none` Auth Fix**: Jenkins logs no longer show "unresolved variable" warnings for `chart-admin-username` and `chart-admin-password`. The local security realm is correctly configured.
3.  **Lib Unit Tests**: All 53 tests passed.

## Steps to Reproduce (Routing Failure)

1.  Run on macOS with OrbStack.
2.  Run `./scripts/k3d-manager deploy_jenkins --enable-vault`.
3.  Observe smoke test failure due to port-forwarding to wrong service/port.

## Fix

- `_jenkins_run_smoke_test` now targets `istio-system/svc/istio-ingressgateway` for the
  macOS tunnel, so TLS terminates at the expected Istio listener (`scripts/plugins/jenkins.sh`).
- The info log now prints the namespace/service being forwarded, which makes troubleshooting
  mismatches easier.
- No other behavior changed: `JENKINS_SMOKE_IP_OVERRIDE=127.0.0.1` is still exported for the
  smoke script, Linux flows still hit the ingress IP directly, and the trap-based cleanup
  remained untouched.

## Verification

- Pending: rerun `CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_jenkins --enable-vault`
  on m4 to capture a successful smoke-test log.
