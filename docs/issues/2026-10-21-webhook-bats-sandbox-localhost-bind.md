# Webhook BATS sandbox localhost-bind restriction

**Date:** 2026-10-21
**Context:** Post-land verification of `cluster-up-progress-thread-context` (`6b324441`)

## Attempt and result

Ran `bats scripts/tests/lib/webhook.bats` from the primary checkout under the default sandbox. HTTP-backed cases failed because the BATS helper could not connect to its local test webhook; pure helper tests passed. Representative verbatim output:

```text
not ok 2 POST with wrong token returns 401
# (in test file scripts/tests/lib/webhook.bats, line 160)
#   `[ "$status" -eq 0 ]' failed
not ok 20 Slack ignores signed unknown and user-less commands without creating anchors
# (in test file scripts/tests/lib/webhook.bats, line 364)
#   `response="$(_slack_event '{"event":{"type":"message","user":"U-unknown","text":"/cluster-status","ts":"1"}}')"' failed with status 7
```

The same suite was rerun with approved permission to bind the local test server. It passed all 68 cases; six live/tunnel cases were environment-gated skips. The dispatcher land gate had also passed the focused pytest and webhook BATS checks before the release branch was pushed.

## Root cause and follow-up

This was a sandbox networking restriction, not a webhook regression. For future BATS suites that start localhost servers, rerun under the appropriate approved permission before treating connection failures as product failures. No code change was needed for this environment issue.
