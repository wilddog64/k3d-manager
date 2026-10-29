# Live verification queue review — 2026-10-29

The operator requested review of eight fixed, offline-verified dashboard rows,
one at a time. The first selected check is the webhook doctor in the operator's
unlocked GUI session, as already prescribed by
[the command-exit-race investigation](2026-10-27-webhook-doctor-command-exit-race.md).
The operator has not yet supplied that check. Existing evidence is insufficient
to mark any of the eight rows live-verified.

A coordinator invocation from the sandbox produced the following actual output:

```text
$ bin/k3dm-webhook-doctor --check
{"classification": "auth_unavailable", "credential": {"lookup_exit": 44, "source": "keychain", "status": "missing"}, "credential_action": "Check the existing k3dm-webhook-token-reader credential (account k3dm); the Keychain lookup did not find it.", "health": {"all_ok": null, "http_responsive": false, "status": "auth_unavailable"}, "health_timeout_seconds": 15, "launchd": {"last_exit_code": null, "pid": 35701, "port": 7443, "status": "loaded"}, "listener": {"listening": true, "status": "listening"}, "log": {"available": true, "error_categories": [], "freshness": "fresh", "modified_utc": "2026-10-29T12:51:15.336539+00:00"}, "mode": "check", "process": {"pids": [], "status": "command_error"}, "recovery_action": null, "recovery_recommended": false, "timestamp_utc": "2026-10-29T12:51:21.994058+00:00"}
```

This invocation was not in the operator's GUI security context. The reported
missing credential and process command error must not be generalized to the
operator's session or treated as proof of a missing item; no authenticated
HTTP check ran. No restart or credential change was performed. Next, have the
operator run `bin/k3dm-webhook-doctor --check` in their unlocked local session
and provide its sanitized JSON. This healthy-path check does not reproduce the
EOF race, locked-Keychain state, or an aggregate timeout.

Other rows remain queued: independent heartbeat requires enrollment and actual
failure/recovery alerts; scanner fail-closed needs evidence of a real scan-error
path (a live vulnerable-candidate block is already recorded); product-catalog
manual rebuild needs its application change on main before a scanner retry;
wrong-port verification includes the unenrolled heartbeat; timeout and
Keychain diagnoses require representative failure evidence; the PR chart needs
repo-filter/empty-history screenshots and timestamp comparison. Do not force
failures or deploy services merely to infer success. See the individual bug
records for acceptance and prerequisites.

## Operator tmux search

The operator said the doctor was running in tmux. Coordinator was on
`m4-air.local`. The first pane-list attempt returned:

```text
error connecting to /private/tmp/tmux-501/default (Operation not permitted)
```

An approved read-only retry listed `work:1.0`, `work:1.1`, `work:2.0`,
`work:3.0`, and `work:4.0` on that socket. A search of the last 3,000
scrollback lines in each for `k3dm-webhook-doctor`, `auth_unavailable`,
`local_http_healthy`, and `health_check_timeout` returned no matching lines.
This does not establish that the operator's command failed: it may be in a
different or nested session, have fallen outside the scrollback, or not have
completed. The operator was asked for the pane location or JSON. No status
changed and no live verification is claimed.

## Operator doctor result from M4

The operator provided `/tmp/webhook-doctor.json`. Its actual contents:

```json
{"classification": "local_http_healthy_external_delivery_unverified", "credential": {"lookup_exit": 0, "source": "keychain", "status": "available"}, "credential_action": null, "health": {"all_ok": true, "http_responsive": true, "status": "healthy_http"}, "health_timeout_seconds": 15, "launchd": {"last_exit_code": null, "pid": 35701, "port": 7443, "status": "loaded"}, "listener": {"listening": true, "status": "listening"}, "log": {"available": true, "error_categories": [], "freshness": "fresh", "modified_utc": "2026-10-29T12:56:15.191792+00:00"}, "mode": "check", "process": {"pids": [35701], "status": "available"}, "recovery_action": null, "recovery_recommended": false, "timestamp_utc": "2026-10-29T12:56:47.202808+00:00"}
```

This confirms the reader lookup succeeded and the doctor observed authenticated
healthy HTTP on port 7443 in the operator's session. It supersedes the sandbox
result for that operator context. It does not reproduce the EOF exit race,
locked-Keychain diagnosis or timeout; heartbeat enrollment and independent
alerting remain unverified. No live-verified flag changed, no restart performed.

## Controlled command-exit check on M4

The operator requested this test. The current checkout contains `b591a13c`;
`shasum -a 256 bin/k3dm-webhook-doctor` returned
`8b296f6fb29d4d4d40f029ba2c2a413e9d77df3999e3922eca6ea7106a319b7e`.
Actual command and output:

```text
$ python3 - <<'PY'
import json, runpy, sys, time
run = runpy.run_path('bin/k3dm-webhook-doctor')['_run']
cases = [
 ('closed-stream-success', "import os,time;os.write(1,b'fixture\\n');os.close(1);os.close(2);time.sleep(.1)", 2),
 ('closed-stream-timeout', 'import os,time;os.close(1);os.close(2);time.sleep(5)', .2),
]
for name, code, deadline in cases:
 started = time.monotonic()
 result = run([sys.executable, '-c', code], timeout=deadline)
 print(json.dumps({'case':name,'elapsed_seconds':round(time.monotonic()-started,3), **result}, sort_keys=True))
 if name == 'closed-stream-success':
  assert result['returncode'] == 0 and not result['timed_out'] and result['stdout'] == 'fixture\n'
 else:
  assert result['returncode'] != 0 and result['timed_out']
print('controlled checks: PASS')
PY
{"case": "closed-stream-success", "elapsed_seconds": 0.156, "output_limited": false, "returncode": 0, "stdout": "fixture\n", "timed_out": false}
{"case": "closed-stream-timeout", "elapsed_seconds": 0.204, "output_limited": false, "returncode": -15, "stdout": "", "timed_out": true}
controlled checks: PASS
$ git merge-base --is-ancestor b591a13c HEAD && printf 'fix commit is present in current checkout\n'
fix commit is present in current checkout
```

Together with the operator's real healthy doctor result above, this establishes
M4 verification of the helper fix using a controlled race. It does not claim
the actual Keychain command encountered the race or that this race caused the
earlier locked-Keychain symptom. No Keychain lock, restart or service mutation.
