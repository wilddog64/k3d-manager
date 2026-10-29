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
