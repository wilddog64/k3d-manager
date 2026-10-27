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

Health-budget regressions cover an eight-second downstream snapshot, a
listening or unknown socket with inconclusive health timeout, confirmed
missing-listener recovery evidence, and a response body sharing the budget
remaining after headers. Four new tests fail against the former four-second
health timeout/restart classification.

Make entrypoint checks: `make -n webhook-doctor` selects --check,
`make -n webhook-doctor DRY_RUN=1` selects --dry-run, and executing the latter
returns the existing no-I/O probe plan. `make help` lists the target.
