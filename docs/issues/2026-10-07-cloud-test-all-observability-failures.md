# Cloud `make-test-all` observability test failures

## What was tested

Cloud request `20261007T112925Z-make-test-all` ran as job `195eff6a`. Metrics publication
completed successfully, but the test suite failed.

## Actual output

```text
[Failure context]
ok 196 oci_restore fails when scp upload to server fails
ok 197 oci_restore fails when remote restore SSH command fails
not ok 198 deploy_observability calls envsubst with $ARGOCD_NAMESPACE and $K3D_MANAGER_BRANCH
# (in test file scripts/tests/lib/observability.bats, line 79)
#   `[ "$status" -eq 0 ]' failed
ok 199 deploy_observability_acg calls envsubst with $ARGOCD_NAMESPACE, $K3D_MANAGER_BRANCH, and $APP_CLUSTER_NAME
not ok 200 deploy_observability_acg falls back to generated Prometheus config when Vault bootstrap write fails
# (in test file scripts/tests/lib/observability.bats, line 250)
#   `[ "$status" -eq 0 ]' failed

[Final output tail]
[k3dm-test-metrics] 1383 cases, 34 failed
[k3dm-test-metrics] metrics pushed: test-all/local
[test-all] metrics log: /var/folders/nc/y0_fv7412472dpg2z7y0yq5w0000gn/T//k3dm-test-all-1791372623.log
make: *** [test-all] Error 2
```

## Root cause assessment

The bounded response identifies cases 198 and 200 as the first actionable failures, but does not
include their complete stub output. Review found that case 198 did not stub the newer ServiceMonitor
helpers and could reach real Helm/host tooling. Case 200 depended on host `htpasswd` while testing
the Vault-write fallback. The aggregate 34-failure count therefore does not establish 34
independent defects. The full cloud log is not present in the returned artifact.

## Follow-up

The focused tests now stub the unrelated ServiceMonitor helpers and deterministic bcrypt generation.
Run the focused observability BATS tests in the same cloud environment and preserve their complete
diagnostic output before closing this issue.
