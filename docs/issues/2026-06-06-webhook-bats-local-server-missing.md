# webhook BATS validation could not complete locally

## What I tested

- Ran `bats scripts/tests/lib/webhook.bats`
- The suite started but all live HTTP checks failed because the local webhook endpoint was not reachable from this session

## Actual output

```text
1..29
not ok 1 POST with wrong token returns 401
# (in test file scripts/tests/lib/webhook.bats, line 44)
#   `[ "$status" -eq 0 ]' failed
not ok 2 POST with no auth header returns 401
# (in test file scripts/tests/lib/webhook.bats, line 53)
#   `[ "$status" -eq 0 ]' failed
not ok 3 POST with correct token returns 202 and job_id
# (in test file scripts/tests/lib/webhook.bats, line 63)
#   `[ "$status" -eq 0 ]' failed
not ok 4 POST body over 4KB returns 413
# (in test file scripts/tests/lib/webhook.bats, line 76)
#   `[ "$status" -eq 0 ]' failed
not ok 5 GET /status with invalid job_id (not hex8) returns 400
# (in test file scripts/tests/lib/webhook.bats, line 84)
#   `[ "$status" -eq 0 ]' failed
not ok 6 GET /status with invalid job_id containing special chars returns 400
# (in test file scripts/tests/lib/webhook.bats, line 92)
#   `[ "$status" -eq 0 ]' failed
not ok 7 GET /status with valid hex8 job_id that does not exist returns 404
# (in test file scripts/tests/lib/webhook.bats, line 100)
#   `[ "$status" -eq 0 ]' failed
not ok 8 GET unknown path returns 404
# (in test file scripts/tests/lib/webhook.bats, line 108)
#   `[ "$status" -eq 0 ]' failed
not ok 9 POST with missing stage field returns 400
# (in test file scripts/tests/lib/webhook.bats, line 118)
#   `[ "$status" -eq 0 ]' failed
not ok 10 POST with invalid stage value returns 400
# (in test file scripts/tests/lib/webhook.bats, line 128)
#   `[ "$status" -eq 0 ]' failed
not ok 11 POST with JSON-injection attempt in chart_version queues job safely
# (in test file scripts/tests/lib/webhook.bats, line 138)
#   `[ "$status" -eq 0 ]' failed
not ok 12 POST /cluster with provider=gcp returns 202 and job_id
# (in test file scripts/tests/lib/webhook.bats, line 148)
#   `[ "$status" -eq 0 ]' failed
not ok 13 POST /cluster with unknown provider defaults to aws (202)
# (in test file scripts/tests/lib/webhook.bats, line 159)
#   `[ "$status" -eq 0 ]' failed
not ok 14 POST /cluster-status with correct token returns 202 and job_id
# (in test file scripts/tests/lib/webhook.bats, line 169)
#   `[ "$status" -eq 0 ]' failed
not ok 15 POST /cluster-status with wrong token returns 401
# (in test file scripts/tests/lib/webhook.bats, line 180)
#   `[ "$status" -eq 0 ]' failed
not ok 16 POST /analyze with correct token returns 202 and job_id
# (in test file scripts/tests/lib/webhook.bats, line 190)
#   `[ "$status" -eq 0 ]' failed
not ok 17 POST /analyze with wrong token returns 401
# (in test file scripts/tests/lib/webhook.bats, line 201)
#   `[ "$status" -eq 0 ]' failed
not ok 18 POST /cluster with response_url stored in job dir
# (in test file scripts/tests/lib/webhook.bats, line 211)
#   `"${_WEBHOOK_URL}/api/v1/cluster")"' failed with status 7
not ok 19 POST /cluster with wrong token returns 401
# (in test file scripts/tests/lib/webhook.bats, line 225)
#   `[ "$status" -eq 0 ]' failed
not ok 20 POST /cluster with action=up returns 202 and job_id
# (in test file scripts/tests/lib/webhook.bats, line 235)
#   `[ "$status" -eq 0 ]' failed
not ok 21 POST /cluster with action=down returns 202 and job_id
# (in test file scripts/tests/lib/webhook.bats, line 246)
#   `[ "$status" -eq 0 ]' failed
not ok 22 POST /cluster with invalid action returns 400
# (in test file scripts/tests/lib/webhook.bats, line 257)
#   `[ "$status" -eq 0 ]' failed
not ok 23 POST /cluster with missing action returns 400
# (in test file scripts/tests/lib/webhook.bats, line 267)
#   `[ "$status" -eq 0 ]' failed
ok 24 Level 1: POST queues job and GET /status returns job output # skip set K3DM_WEBHOOK_LIVE=1 to enable
ok 25 Level 1: GET /status output field is non-empty after job completes # skip set K3DM_WEBHOOK_LIVE=1 to enable
ok 26 Level 2: POST current chart version returns success without running make up # skip set K3DM_WEBHOOK_LEVEL2=1 to enable (requires cluster)
ok 27 Level 3: tunnel rejects wrong token with 401 # skip set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)
ok 28 Level 3: tunnel unknown path returns 404 (auth passes, routing fails) # skip set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)
ok 29 Level 3: tunnel POST with real token queues job and returns 202 # skip set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)
```

## Root cause

The test suite expects a live webhook endpoint, but this session did not have the local webhook server running or reachable at the configured URL, so the HTTP assertions could not execute.

## Recommended follow-up

- Re-run `bats scripts/tests/lib/webhook.bats` in an environment where the webhook LaunchAgent is up and the local endpoint resolves
- If the webhook is supposed to be exercised live, start/restart it first and then rerun the suite
