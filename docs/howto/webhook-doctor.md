# Webhook incident doctor

`bin/k3dm-webhook-doctor` provides a read-only local snapshot for the
`com.k3d-manager.webhook` LaunchAgent. The default invocation (same as
`--dry-run`) prints the probe plan and does not inspect Keychain, launchd,
processes, listeners, logs, or the network.

On the m4 host, run `bin/k3dm-webhook-doctor --check` to collect timestamped
JSON. It reports launchd job presence, parsed PID and last exit code, TCP/9000
listener presence, log modification time and bounded error categories, then
probes only `http://127.0.0.1:9000/api/v1/health?quick=1` with the reader token held in
memory. The dedicated opener bypasses proxy settings and refuses redirects, so
the authorization header stays on the fixed loopback request. The reader token is read from `K3DM_WEBHOOK_TOKEN_READER` or macOS
Keychain; no token, launchd environment, process arguments, or raw log lines
are included in output. The request timeout is four seconds and log inspection
is capped at 64 KiB / 80 lines. Command output capture is capped at 16 KiB and
the health response body at 64 KiB with a total four-second deadline. The probe
does not accept a remote URL.

`local_http_healthy_external_delivery_unverified` describes a valid handler
response with all named service checks true. A successful handler response
with a false service check is classified as dependencies degraded; an empty
service list or any `ok: null` result is dependencies unknown. `all_ok` must
match the service checks, and empty or inconsistent responses cannot be
classified as healthy. A responsive handler does not establish that Slack or
external delivery works. A public endpoint failure alone does not establish a
local webhook failure. Authentication failures, invalid responses, HTTP
errors, timeouts, and launchd command errors remain distinct. Command
unavailable, timeout, permission/unknown errors are not treated as a verified
missing job. A listener or process alone is never classified as healthy.

The doctor never calls recovery. It recommends recovery only for a launchd job
reported missing by launchctl or a timed-out local health request. Missing
credentials and diagnostic command failures do not recommend a restart. If
reliable local evidence shows the webhook is unhealthy, an operator may choose to run
`make restart-webhook` once from the repository on m4. That supported action
reloads the webhook LaunchAgent and also restarts cloud-bridge. Do not loop it.
Capture the command result, then repeat local functional health and verify a
benign end-to-end Slack/cloud-bridge response. If local HTTP works but external
delivery does not, investigate ingress/bridge before considering a restart.

The October 26 offsite incident remains unconfirmed until the operator records
local evidence. This helper and its offline tests do not provide live E1/E2
evidence and do not change the incident's status.
