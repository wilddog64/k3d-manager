# k3dm-webhook BATS mismatch: path normalization and JSON formatting

## What I tested

- Ran `python3 -m py_compile bin/k3dm-webhook`
- Ran `shellcheck scripts/tests/lib/webhook.bats`
- Ran `bats scripts/tests/lib/webhook.bats`

## Actual output

Initial `bats scripts/tests/lib/webhook.bats` run:

```text
1..17
ok 1 POST with wrong token returns 401
ok 2 POST with no auth header returns 401
not ok 3 POST with correct token returns 202 and job_id
# (in test file scripts/tests/lib/webhook.bats, line 64)
#   `[[ "$output" == *'"status":"queued"'* ]]' failed
ok 4 POST body over 4KB returns 413
ok 5 GET /status with invalid job_id (not hex8) returns 400
not ok 6 GET /status with invalid job_id containing special chars returns 400
# (in test file scripts/tests/lib/webhook.bats, line 93)
#   `[ "$output" = "400" ]' failed
ok 7 GET /status with valid hex8 job_id that does not exist returns 404
ok 8 GET unknown path returns 404
ok 9 POST with missing stage field returns 400
ok 10 POST with invalid stage value returns 400
not ok 11 POST with JSON-injection attempt in chart_version queues job safely
# (in test file scripts/tests/lib/webhook.bats, line 139)
#   `[[ "$output" == *'"status":"queued"'* ]]' failed
ok 12 Level 1: POST queues job and GET /status returns job output # skip set K3DM_WEBHOOK_LIVE=1 to enable
ok 13 Level 1: GET /status output field is non-empty after job completes # skip set K3DM_WEBHOOK_LIVE=1 to enable
ok 14 Level 2: POST current chart version returns success without running make up # skip set K3DM_WEBHOOK_LEVEL2=1 to enable (requires cluster)
ok 15 Level 3: tunnel rejects wrong token with 401 # skip set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)
ok 16 Level 3: tunnel unknown path returns 404 (auth passes, routing fails) # skip set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)
ok 17 Level 3: tunnel POST with real token queues job and returns 202 # skip set K3DM_WEBHOOK_LEVEL3=1 to enable (requires tunnel)
```

## Root cause

- The webhook API returned JSON with default spacing, so the BATS checks looking for exact compact substrings like `"status":"queued"` did not match.
- The malformed path test used `../../etc`, which curl normalized to `/api/etc`, so the server treated it as a generic unknown route instead of a malformed API path and returned 404 instead of 400.

## Recommended follow-up

- Keep compact JSON output from `bin/k3dm-webhook`.
- Treat malformed `/api/*` routes outside `/api/v1/` as a 400 so the test expectations remain stable even with curl path normalization.
