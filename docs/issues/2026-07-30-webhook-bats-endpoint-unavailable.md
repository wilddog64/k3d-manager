# Webhook BATS Endpoint Unavailable

## What Was Tested

The documentation-only CVE remediation guide change ran the focused regression suites:

```bash
bats scripts/tests/lib/webhook.bats
bats scripts/tests/plugins/app_cve_scan.bats
bats scripts/tests/plugins/trivy_operator_observability.bats
```

## Actual Output

```text
1..44
not ok 1 POST with wrong token returns 401
# (in test file scripts/tests/lib/webhook.bats, line 129)
#   `[ "$status" -eq 0 ]' failed
...
not ok 33 POST /cluster with response_url stored in job dir
# (in test file scripts/tests/lib/webhook.bats, line 496)
#   `"${_WEBHOOK_URL}/api/v1/cluster")"' failed with status 7
...
1..9
ok 1 all-skipped run exits 1 with the fatal zero-match diagnostic
ok 2 vulnerable deployed image with vulnerable latest dispatches rebuild instead of promotion
ok 3 vulnerable deployed image with clean latest promotes exact digest via application patch
ok 4 registry-less trivy-operator repository form still matches and promotes
ok 5 digest resolution reads busybox-style indented lowercase headers
ok 6 clean frontend image is scanned and skipped
ok 7 clean payment image is scanned and skipped
ok 8 rebuild path without GH token returns non-zero
ok 9 missing immutable sha candidate skips promotion instead of falling back to latest
1..7
ok 1 trivy observability: charts pin trivy-operator 0.34.0 in both application sets
ok 2 trivy observability: chart values enable serviceMonitor scraping
ok 3 trivy observability: scanner image tag is explicitly pinned in both values files
ok 4 trivy observability: both values files enable the built-in trivy server (ClientServer mode)
ok 5 trivy observability: acg trivy application set uses the acg-specific values file
ok 6 trivy observability: dashboard exposes log and metric panels for trivy-system
ok 7 trivy observability: prometheus rule and alertmanager route cover scan job failures
```

## Root Cause

The HTTP-oriented cases in `scripts/tests/lib/webhook.bats` could not reach the
test webhook endpoint. The direct curl failure was status `7` (connection failed),
while source-level cases in the same suite passed. The CVE guide changes do not
touch the webhook server or its test harness.

## Recommended Follow-Up

Restore or diagnose the webhook test-server startup path, then rerun
`bats scripts/tests/lib/webhook.bats`. The `app_cve_scan` and Trivy
observability suites are currently green.
