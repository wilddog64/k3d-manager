# Webhook BATS requires localhost bind permission

## What was tested

During verification of `2026-10-15-slack-k3dm-help-no-response-during-cluster-up`, the canonical
webhook BATS suite was first run inside the default sandbox, then rerun through the approved
elevated path. The suite starts a temporary server on `127.0.0.1:17443` from `setup_file`.

## Actual sandbox output

```text
not ok 2 POST with wrong token returns 401
#   `[ "$status" -eq 0 ]' failed
not ok 3 POST with no auth header returns 401
#   `[ "$status" -eq 0 ]' failed
not ok 20 Slack ignores signed unknown and user-less commands without creating anchors
#   `response="$(_slack_event '{"event":{"type":"message","user":"U-unknown","text":"/cluster-status","ts":"1"}}')"' failed with status 7
Test log unavailable (failed to create log file).
```

The canonical tripwire run outside the sandbox passed `1..68`; five integration cases were
expected skips. Tripwire reported:

```text
[tripwire] blocked 74 call(s) to host tools; none reached a real binary:
     37 security	find-generic-password -s k3dm-webhook-token-reader -a k3dm -w
     37 security	find-generic-password -s k3dm-webhook-token-cloud-runner -a k3dm -w
```

## Root cause

The sandbox blocked the BATS harness from opening its local HTTP listener, so HTTP-level tests
failed to connect. This did not reproduce outside the sandbox and was not a product-code failure.

## Follow-up

When running `scripts/tests/lib/webhook.bats` in a restricted execution environment, permit its
temporary localhost listener or use an approved environment that allows loopback sockets. No code
change is recommended.
