# M2 E2E acceptance: current image/API contract mismatch

## What was attempted

On 2026-08-25, after M2 bootstrap and preflight passed, the required passing
run was retried with:

```text
E2E_M2_SSH_HOST=m2-air.local E2E_M2_PUBLISH_BACK_HOST=cliang@m4-air.local \
E2E_M2_PUBLISH_BACK_KEY=$HOME/.ssh/e2e-m4-publisher \
make e2e-remote RUNNER=m2
```

The stale vCluster left by the previous attempt was removed by its exact name
before retrying. The E2E image cold-pulled successfully on M2 (about 890 MB),
and the Playwright job started.

## Actual result

The run published this result to the M4 hub:

```text
INFO: [e2e] Summary written to /Users/cliang/.k3dm/e2e/1787708603-5833.json (exit_code=1)
INFO: [e2e-publish] applied result for run 1787708603-5833 (runner=m2, result=fail)
INFO: [e2e-remote] result 1787708603-5833.json published to M4 hub
INFO: [e2e-remote] dispatch exit 1; transcript: /Users/cliang/.k3dm/e2e/dispatch/m2-20260826T014322Z.log
make: *** [e2e-remote] Error 1
```

The retained summary was:

```json
{
  "candidate_digest": null,
  "commit": "f5a40988d11f00e579d5bad521b13aa8d189ce40",
  "duration_seconds": 67.869,
  "exit_code": 1,
  "failed": 45,
  "passed": 12,
  "phase": "recording-result",
  "project": "api+flows",
  "result": "fail",
  "run_id": "1787708603-5833",
  "runner": "m2",
  "service": "product-catalog",
  "tier": "vcluster",
  "total": 102
}
```

Representative failures show the deployed APIs return the standard `{data: …,
success: true}` envelope while the current E2E client/tests assert fields at the
top level:

```text
Expected path: "id"
Received value: {"data": {"createdAt": "2026-08-26T01:50:53.210812208Z", "currency": "USD", "customerId": "e2e-1787709053208-blvpa", "expiresAt": "2026-09-02T01:50:53.210812208Z", "id": "352e4947-0cd0-4143-9dfc-a12a3c749a74", "itemCount": 0, "items": [], "totalAmount": 0, "updatedAt": "2026-08-26T01:50:53.210812208Z"}, "success": true}
    at /e2e/tests/api/cart.spec.ts:32:20
```

```text
Expected: "number"
Received: "string"
    at /e2e/tests/api/products.spec.ts:86:38
```

The log also contains repeated `Order cleanup skipped: orders is not iterable`
messages, consistent with the same envelope mismatch. This is not an M2
transport or publisher failure.

## Publication and cleanup checks

The latest M2 result is present once in `platform-ops`:

```text
{"run_id": "1787708603-5833", "tier": "vcluster", "runner": "m2", "service": "product-catalog", "project": "api+flows", "candidate_digest": "", "passed": "false", "total": "102", "failed": "45", "duration_seconds": "67.869", "timestamp": "2026-08-26T01:52:03.423304+00:00", "commit": "f5a40988d11f00e579d5bad521b13aa8d189ce40"}
```

The intentional invalid-digest run also published as a failed result. Both
required result paths therefore exercised publication, but the passing gate is
blocked by the test/image contract mismatch.

## Follow-up

Align the E2E image's API client/tests with the deployed response envelope and
numeric price contract, rebuild/publish `:latest`, then rerun the passing M2
acceptance. Do not treat this run as a passing acceptance result.
