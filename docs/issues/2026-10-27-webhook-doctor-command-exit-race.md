# Webhook doctor: command EOF is not process success/failure

## Operator repeat after port correction

The operator ran `bin/k3dm-webhook-doctor --check` and supplied:

```json
{"classification": "auth_unavailable", "health": {"all_ok": null, "http_responsive": false, "status": "auth_unavailable"}, "launchd": {"last_exit_code": null, "pid": 4295, "port": 7443, "status": "loaded"}, "listener": {"listening": true, "status": "listening"}, "log": {"available": true, "error_categories": [], "freshness": "fresh", "modified_utc": "2026-10-27T12:41:14.929147+00:00"}, "mode": "check", "process": {"pids": [4295], "status": "available"}, "recovery_action": "make restart-webhook (operator-controlled; restarts cloud-bridge too; at most once initially)", "recovery_recommended": false, "timestamp_utc": "2026-10-27T12:42:06.930929+00:00"}
```

Port7443/listener is now correct. The result did not probe authenticated HTTP
because the credential was unavailable; no recovery was recommended. The
underlying operator credential-context cause has not been established.
Previously verified current local health and Slack job a13d5831 are unchanged
evidence, not an explanation of this failed lookup.

## Offline reproduction of a distinct command-helper defect

A controlled child writes a fixture string, closes both stdout/stderr, waits
0.1 seconds then exits successfully. The old `_run` terminated it as soon as
the output pipe closed, even with time remaining. Actual result:

```text
{'returncode': -15, 'timed_out': False, 'output_limited': False}
```

This can cause a successful lookup to be rejected. It is a demonstrated
helper defect and a possible explanation for operator auth_unavailable, not
a proven Keychain incident cause. No real credential was used in the fixture.
Closing stdout alone kept stderr open and returned success; closing both
streams reproduced the defect.

Two new regressions against original code:

```text
FF                                                                       [100%]
=================================== FAILURES ===================================
__________ test_command_waits_for_success_after_output_streams_close ___________

    def test_command_waits_for_success_after_output_streams_close():
        result = doctor._run([sys.executable, "-c",
            "import os,time;os.write(1,b'fixture-reader-token\\n');os.close(1);os.close(2);time.sleep(.1)"])
>       assert result["returncode"] == 0
E       assert -15 == 0

scripts/tests/bin/test_webhook_doctor.py:327: AssertionError
____________ test_command_with_closed_streams_still_obeys_deadline _____________

    def test_command_with_closed_streams_still_obeys_deadline():
        result = doctor._run([sys.executable, "-c",
            "import os,time;os.close(1);os.close(2);time.sleep(5)"], timeout=0.1)
>       assert result["timed_out"] is True
E       assert False is True

scripts/tests/bin/test_webhook_doctor.py:335: AssertionError
=========================== short test summary info ============================
FAILED scripts/tests/bin/test_webhook_doctor.py::test_command_waits_for_success_after_output_streams_close
FAILED scripts/tests/bin/test_webhook_doctor.py::test_command_with_closed_streams_still_obeys_deadline
2 failed, 24 deselected in 0.33s
```

## Correction and actual final gates

Fix `b591a13c803b44377fcea91207ea68142a9fdf5c` waits for process exit within
the remaining command deadline after output closes. A child still running
after that deadline is terminated and correctly marked timed_out; the output
cap and bounded termination remain in place. No Keychain/service settings or
credentials changed, and the doctor still performs no recovery.

```text
..........................                                               [100%]
26 passed in 0.45s
1..5
ok 1 restart-webhook reloads the plist with bootout then bootstrap, never kickstarting the webhook
ok 2 restart-webhook continues to bootstrap when bootout reports the job is not loaded
ok 3 restart-webhook still restarts the cloud bridge
ok 4 restart-webhook retries bootstrap twice then reports success
ok 5 restart-webhook fails after five bootstrap attempts and skips cloud bridge
All checks passed!
```

Ruff and diff check passed. Staged `_agent_lint`, `_agent_audit` and checkpoint
hook passed with no bypass. Production code is Python; no production shell
file was changed. ShellCheck is not applicable to this correction.

On continuation, remote had17 concurrent documentation commits and local had
one code commit. Fetched and merged them with `--no-commit`, ran staged gates
and committed merge21e235d1. No force push or shared-branch rebase.

Next single operator check: rerun the doctor in the same shell. Actual local
credential behavior remains pending this result; do not mark the helper's
offline regression as live verification or restart the webhook.

## Operator recheck after fix — credential context unresolved

Operator supplied this result after the fix was pushed:

```json
{"classification": "auth_unavailable", "health": {"all_ok": null, "http_responsive": false, "status": "auth_unavailable"}, "launchd": {"last_exit_code": null, "pid": 4295, "port": 7443, "status": "loaded"}, "listener": {"listening": true, "status": "listening"}, "log": {"available": true, "error_categories": [], "freshness": "fresh", "modified_utc": "2026-10-27T22:29:14.735005+00:00"}, "mode": "check", "process": {"pids": [4295], "status": "available"}, "recovery_action": "make restart-webhook (operator-controlled; restarts cloud-bridge too; at most once initially)", "recovery_recommended": false, "timestamp_utc": "2026-10-27T22:30:13.088991+00:00"}
```

The command-exit fix did not resolve this operator credential symptom. Port
7443 is listening and no recovery is recommended. This result did not test
authenticated HTTP. The race remains independently reproduced/fixed but is
not established as the cause of this context's unavailable credential.

Coordinator then inspected only lookup metadata, never printing the value,
using the same bounded runner against /usr/bin/security:

```json
{"security_path": "/usr/bin/security", "reader_env_present": false, "lookup_status": "complete", "lookup_exit": 0, "reader_value_present": true}
```

The reader item exists and is retrievable in the coordinator execution
context; no value is recorded here. That does not prove accessibility from
the operator shell. Source review confirms the doctor and server both look
for service k3dm-webhook-token-reader / account k3dm, with the same reader env
name. There is no admin-token fallback, by design. No credential was rotated,
exported, copied to a file, or disclosed.

Next single operator diagnostic uses /usr/bin/security with stdout/stderr
captured in memory and prints only executable resolution, exit status,
nonempty-success boolean and elapsed time (or a bounded timeout). This will
distinguish a failed lookup from a helper-level issue without exposing a
token. Actual operator lookup status/cause remains pending; no new code fix
or whole-incident closure is claimed. GHCR runtime scan and subsequent live
items remain queued while this steering is investigated.

This is an evidence-only update: implementation tests are unchanged (26
Python/5 BATS recorded above); no additional code test or ShellCheck needed.
Normal staged lint/audit, doc links and checkpoint hooks remain enabled.

## Operator native lookup exit36 — session/access hypothesis

The targeted metadata probe returned:

```json
{"security_path": "/usr/bin/security", "lookup_exit": 36, "credential_present": false, "elapsed_seconds": 0.03}
```

This was a quick native lookup failure, not the four-second command timeout.
credential_present=false here is a success-gated boolean, so it does not
prove that the item is missing. The binary path matches /usr/bin/security.

Read-only local OS diagnostics:

```text
$ /usr/bin/security error -25308
Error: 0xFFFF9D24 -25308 User interaction is not allowed.
$ /usr/bin/security error 36
Error: 0x00000024 36 unknown error 36=24
$ Python integer calculation
-25308 modulo 256 = 36
```

Installed Apple SDK SecBase.h also declares errSecInteractionNotAllowed as
-25308. Apple primary references:
[error definition](https://developer.apple.com/documentation/security/errsecinteractionnotallowed),
[security CLI source](https://github.com/apple-oss-distributions/Security/blob/main/SecurityTool/macOS/security.c),
[password lookup source](https://github.com/apple-oss-distributions/Security/blob/main/SecurityTool/macOS/keychain_find.c).

Inference: exit36 is consistent with a truncated -25308 interaction-not-allowed
status and a shell/security-session access restriction. Exit codes are
truncated, so this alone does not prove the exact native OSStatus, a locked
keychain, or tmux as the cause. Coordinator context previously retrieved the
reader item successfully without disclosure. No additional code change or
credential rotation is justified by the current evidence.

Next single operator check: fresh local GUI iTerm2 tab outside tmux/remote
session, run absolute security lookup with stdout redirected to /dev/null,
then print exit status. Native stderr remains visible to confirm any error;
token is never printed. No password in argv, no broad ACL change, no restart.
The coordinator did not unlock a keychain, change permissions or run UI
automation. GHCR runtime remains queued until this user steering is resolved.

Evidence-only record; code/tests unchanged. Normal doc links and staged
audit/lint/checkpoint gates apply.
