# Phase 4 verification still hits pre-existing ArgoCD test failures

## What I ran

Full repository test discovery:

```text
bats $(rg --files scripts/tests -g '*.bats')
```

## Actual output

```text
not ok 272 deploy_argocd --help shows usage
# (in test file scripts/tests/plugins/argocd.bats, line 12)
#   `[[ "$output" == *"Usage: deploy_argocd"* ]]' failed
...
not ok 276 _argocd_ensure_logged_in uses plaintext non-interactive login
# (in test file scripts/tests/plugins/argocd.bats, line 46)
#   `[[ "${argocd_calls[1]}" == *"login localhost:8080 --username admin --password fake-pass --plaintext --skip-test-tls --insecure --grpc-web"* ]]' failed
```

The suite finished with:

```text
1..288
```

and exited non-zero because of those two failures.

## Root cause

These are pre-existing ArgoCD test gaps outside the Phase 4 subtree wiring work. They are not caused by the lib-acg subtree import or the plugin stubs changed in this task.

## Recommended follow-up

Fix the ArgoCD help text and login flag regression separately, then rerun the full suite.
