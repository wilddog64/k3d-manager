# 2026-06-13 — webhook live BATS tests require a running service

## What I tested

- Ran `bats scripts/tests/lib` after implementing the `k3s-hostinger` provider changes.

## Actual output

```text
1..219
ok 1 _acg_write_credentials writes [default] profile to ~/.aws/credentials
ok 2 _acg_write_credentials sets file permissions to 600
...
ok 189 _run_command: --prefer-sudo flag is accepted without error
ok 190 test_jenkins trap removes auth file
not ok 191 POST with wrong token returns 401
# (in test file scripts/tests/lib/webhook.bats, line 44)
#   `[ "$status" -eq 0 ]' failed
not ok 192 POST with no auth header returns 401
# (in test file scripts/tests/lib/webhook.bats, line 53)
#   `[ "$status" -eq 0 ]' failed
not ok 193 POST with correct token returns 202 and job_id
# (in test file scripts/tests/lib/webhook.bats, line 63)
#   `[ "$status" -eq 0 ]' failed
not ok 194 POST body over 4KB returns 413
# (in test file scripts/tests/lib/webhook.bats, line 76)
#   `[ "$status" -eq 0 ]' failed
not ok 195 GET /status with invalid job_id (not hex8) returns 400
# (in test file scripts/tests/lib/webhook.bats, line 84)
#   `[ "$status" -eq 0 ]' failed
...
not ok 208 POST /cluster with response_url stored in job dir
# (in test file scripts/tests/lib/webhook.bats, line 211)
#   `"${_WEBHOOK_URL}/api/v1/cluster")"' failed with status 7
...
not ok 213 POST /cluster with missing action returns 400
# (in test file scripts/tests/lib/webhook.bats, line 267)
#   `[ "$status" -eq 0 ]' failed
ok 214 Level 1: POST queues job and GET /status returns job output # skip set K3DM_WEBHOOK_LIVE=1 to enable
ok 215 Level 1: GET /status output field is non-empty after job completes # skip set K3DM_WEBHOOK_LIVE=1 to enable
ok 216 Level 2: POST current chart version returns success without running make up # skip set K3DM_WEBHOOK_LEVEL2=1 to enable (requires cluster)
ok 217 Level 3: tunnel rejects wrong token with 401 # skip set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)
ok 218 Level 3: tunnel unknown path returns 404 (auth passes, routing fails) # skip set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)
ok 219 Level 3: tunnel POST with real token queues job and returns 202 # skip set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)
```

## Root cause

The broad `scripts/tests/lib` bundle includes live webhook tests that require a running webhook service and its associated environment. Those tests are not set up in this session, so the live webhook cases fail even though the provider-specific work is unrelated.

## Recommended follow-up

- Run the live webhook BATS cases only in an environment where the webhook service is started and the required webhook variables are configured.
- Keep using `scripts/tests/lib/provider_contract.bats` for the provider wiring changes made in this task.
