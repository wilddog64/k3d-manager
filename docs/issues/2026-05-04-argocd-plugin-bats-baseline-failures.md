# argocd plugin BATS baseline failures

## What was tested
- `bats scripts/tests/plugins/argocd.bats`

## Actual output
```text
1..7
not ok 1 deploy_argocd --help shows usage
# (in test file scripts/tests/plugins/argocd.bats, line 12)
#   `[[ "$output" == *"Usage: deploy_argocd"* ]]' failed
ok 2 deploy_argocd skips when CLUSTER_ROLE=app
ok 3 deploy_argocd_bootstrap --help shows usage
ok 4 deploy_argocd_bootstrap no-ops when skipping all resources
not ok 5 _argocd_ensure_logged_in uses plaintext non-interactive login
# (in test file scripts/tests/plugins/argocd.bats, line 46)
#   `[[ "${argocd_calls[1]}" == *"login localhost:8080 --username admin --password fake-pass --plaintext --skip-test-tls --insecure --grpc-web"* ]]' failed
ok 6 _argocd_deploy_appproject fails when template missing
ok 7 ARGOCD_NAMESPACE defaults to cicd
```

## Root cause
- These failures are unrelated to the Argo CD readiness timeout fix.
- `deploy_argocd --help` still does not emit the expected usage string in this test harness.
- `_argocd_ensure_logged_in` now logs in with stdin-based password handling, while the test still expects a `--password` invocation.

## Recommended follow-up
- Update the help-path test to match the current `deploy_argocd` help output.
- Update the login test to assert the current stdin-based `argocd login` contract.
