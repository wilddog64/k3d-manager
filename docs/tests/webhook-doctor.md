# Webhook doctor tests

Run `pytest -q scripts/tests/bin/test_webhook_doctor.py` and
`bats scripts/tests/bin/restart_webhook.bats`.

The Python suite injects command and HTTP fixtures; it never invokes launchd,
Keychain, a real listener, or recovery. It covers dry-run isolation, bounded
command capture and response deadlines, exact quick-health URL and reader
header, redirect/proxy isolation, schema validation including valid `ok: null`,
contradictory and empty payloads, and distinct diagnostic command/auth/HTTP
outcomes. Redirect behavior is exercised through a fake HTTP transport, so no
network request leaves the test process. The original incident remains pending
operator E1/E2 evidence.

Credential regressions also cover locked/inaccessible Keychain versus missing
item, lookup timeout/output cap/failure/empty value, environment-token bypass,
secret redaction, no HTTP probe without credentials, no restart or unlock
calls, and observing an unlock on the next check without a cached token.
Four new credential-state tests fail on the prior generic-auth output.
