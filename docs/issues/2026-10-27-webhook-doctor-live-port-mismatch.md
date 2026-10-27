# Webhook doctor live check: incorrect port and separate auth context

## Operator result

User first identified iTerm2 then corrected the source to tmux, and supplied
the actual JSON below. Computer-use tool explicitly rejected iTerm2 access:

```text
Computer Use is not allowed to use the app 'com.googlecode.iterm2' for safety reasons.
```

No alternative UI automation was used. CLI tmux enumeration found five
k3d-manager panes; a joined5000-line scrollback search found no doctor command
or classification JSON. The user's pasted result is the operator evidence:

```json
{"classification": "auth_unavailable", "health": {"all_ok": null, "http_responsive": false, "status": "auth_unavailable"}, "launchd": {"last_exit_code": null, "pid": 4295, "status": "loaded"}, "listener": {"listening": false, "status": "no_listener"}, "log": {"available": true, "error_categories": ["exception"], "freshness": "fresh", "modified_utc": "2026-10-27T12:17:14.301764+00:00"}, "mode": "check", "process": {"pids": [4295], "status": "available"}, "recovery_action": "make restart-webhook (operator-controlled; restarts cloud-bridge too; at most once initially)", "recovery_recommended": false, "timestamp_utc": "2026-10-27T12:17:20.058420+00:00"}
```

This is auth_unavailable, not proof of a dead HTTP handler: no authenticated
health request ran. No recovery was recommended by the operator's command.
The reason the credential was unavailable in that context remains unknown.
No credential was changed or printed.

## Independent read-only observations before correction

Because iTerm2 was blocked, coordinator transparently ran the same diagnostic
directly (not represented as reading the operator's pane). That returned
local_http_unresponsive at12:19:04Z because it had a reader credential but
probed the wrong port9000. Independent process/listener check:

```text
  PID     ELAPSED COMM
 4295 01-11:19:44 /opt/homebrew/Cellar/python@3.15/3.15.1/Frameworks/Python.framework/Versions/3.15/Resources/Python.app/Contents/MacOS/Python
COMMAND  PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
Python  4295 cliang    3u  IPv4 0x532d94061d900728      0t0  TCP 127.0.0.1:7443 (LISTEN)
```

`scripts/lib/webhook/config.py` defaults K3DM_WEBHOOK_PORT to7443. The new
doctor hardcoded9000; heartbeat default/example had the same mistake. This
invalidates the old no_listener and unresponsive findings as outage evidence.
No restart was performed. Historical incident root cause is still unknown.

## Correction and regression evidence

Implementation `2b93434e893ff0417946c550deecbecb1443021d` changes default
doctor/heartbeat/example to7443. Doctor reads a validated K3DM_WEBHOOK_PORT
from bounded loaded-job output and uses the same port for listener and HTTP.
Unknown/invalid configuration is not interpreted as a missing listener or
allowed to trigger recovery. No service, launchd, secret or scheduler changed.

New expectations on original source:

```text
FAILED scripts/tests/bin/test_webhook_doctor.py::test_health_probe_keeps_handler_and_dependency_health_separate
FAILED scripts/tests/bin/test_webhook_doctor.py::test_health_opener_does_not_forward_credentials_after_redirect
FAILED scripts/tests/bin/test_webhook_doctor.py::test_launchd_facts_do_not_return_environment_or_raw_output
FAILED scripts/tests/bin/test_webhook_doctor.py::test_loaded_webhook_port_is_used_for_listener_and_health
FAILED scripts/tests/bin/test_webhook_doctor.py::test_launchd_port_defaults_to_server_and_validates_override
FAILED scripts/tests/bin/test_heartbeat.py::test_webhook_default_and_enrollment_example_use_server_port
6 failed, 46 passed in 0.35s
```

During fixture adaptation, two old mocked health functions initially rejected
the new port keyword; corrected their signatures. Production code did not
raise those fixture-only TypeErrors. Final full focused output:

```text
........................................................................ [ 44%]
........................................................................ [ 89%]
.................                                                        [100%]
161 passed in 3.89s
1..8
ok 1 restart-webhook reloads the plist with bootout then bootstrap, never kickstarting the webhook
ok 2 restart-webhook continues to bootstrap when bootout reports the job is not loaded
ok 3 restart-webhook still restarts the cloud bridge
ok 4 restart-webhook retries bootstrap twice then reports success
ok 5 restart-webhook fails after five bootstrap attempts and skips cloud bridge
ok 6 heartbeat: dry run renders intent without provider calls
ok 7 heartbeat: templates contain no enrolled endpoint
ok 8 heartbeat: documented commands execute directly
All checks passed!
```

Audit initially rejected replacing the incorrect9000 assertions. Added the
required explicit assertion-replacement explanation preserving redaction and
port checks; reran audit/lint and normal checkpoint hook successfully. No
bypass was used. ShellCheck warning-level heartbeat BATS clean; production
code is Python and Ruff passed.

## Corrected direct live result (coordinator, read-only)

```json
{"classification": "local_http_healthy_external_delivery_unverified", "health": {"all_ok": true, "http_responsive": true, "status": "healthy_http"}, "launchd": {"last_exit_code": null, "pid": 4295, "port": 7443, "status": "loaded"}, "listener": {"listening": true, "status": "listening"}, "log": {"available": true, "error_categories": ["exception"], "freshness": "fresh", "modified_utc": "2026-10-27T12:24:14.422978+00:00"}, "mode": "check", "process": {"pids": [4295], "status": "available"}, "recovery_action": "make restart-webhook (operator-controlled; restarts cloud-bridge too; at most once initially)", "recovery_recommended": false, "timestamp_utc": "2026-10-27T12:24:33.733843+00:00"}
```

Local handler responds at the correct port; all reported dependency checks
are healthy. No restart is warranted. Fresh exception-category log evidence
is historical/contextual; it does not negate successful current health.
This direct result does not resolve why the operator context lacked a reader
credential, or prove Slack/cloud-bridge end-to-end delivery. The October26
incident remains OPEN. Heartbeat enrollment/alert delivery remains untested.

Next single operator check: Slack `/k3dm fix-list`, reader allowlisted and
read-only; confirm actual completed result delivery rather than acknowledgment
alone. Do not run recovery. Other batch live checks remain queued.
