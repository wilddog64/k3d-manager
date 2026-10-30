# Webhook doctor health timeout did not establish a dead handler

## Operator result after Keychain unlock

```json
{"classification": "local_http_unresponsive", "credential": {"lookup_exit": 0, "source": "keychain", "status": "available"}, "credential_action": null, "health": {"all_ok": null, "http_responsive": false, "status": "local_timeout"}, "launchd": {"last_exit_code": null, "pid": 4295, "port": 7443, "status": "loaded"}, "listener": {"listening": true, "status": "listening"}, "log": {"available": true, "error_categories": [], "freshness": "fresh", "modified_utc": "2026-10-27T22:43:14.658228+00:00"}, "mode": "check", "process": {"pids": [4295], "status": "available"}, "recovery_action": "make restart-webhook (operator-controlled; restarts cloud-bridge too; at most once initially)", "recovery_recommended": true, "timestamp_utc": "2026-10-27T22:43:40.323206+00:00"}
```

Reader credential is now available; the earlier Keychain access issue is
resolved in this observation. The doctor timed out while job/PID/listener
remained present and recommended a restart. Coordinator advised holding
recovery pending independent evidence. No restart was run.

## Source and independent read-only checks

`/api/v1/health?quick=1` still runs `_smoke_test_services(retries=1, quick=True)`.
Quick mode returns after parallel downstream HTTP checks, each using an
eight-second request timeout. The doctor used only four seconds and treated
any aggregate timeout as proof of local_http_unresponsive/recovery needed.
That inference is unsound: downstream health work is distinct from handler
liveness.

Bounded current requests, credentials only in memory:

```json
{"probe": "unauthenticated_handler", "http_status": 401, "elapsed_seconds": 0.146}
{"probe": "authenticated_quick_health", "budget_seconds": 15, "elapsed_seconds": 3.438, "status": "healthy_http", "http_responsive": true, "all_ok": true}
```

The expected credential-free401 is returned before auth lookup/dependency
work in the server. It proves a responsive HTTP handler, not service health.
The authenticated response separately establishes healthy current results.
The measured successful request did not exceed four seconds; we do not claim
to have measured the cause/duration of the operator's earlier timeout. It
could be transient or slow downstream/auth work. No particular dependency or
historical outage cause was inferred, and no raw body/token was logged.

## Correction

Implementation `eafe42da71f6243f9613dc85f53f92f9e7ae0182` separates the
15-second health budget from four-second local command probes. Response
body reading uses the budget remaining after headers. Output explicitly
reports health_timeout_seconds.

With a present or unknown listener, a health timeout is health_check_timeout,
all_ok remains null, and no restart action is recommended. A verified missing
job or missing listener without a responsive HTTP result remains independent
recovery evidence. Doctor remains read-only; no server behavior changes.

## Actual pre-fix regressions

```text
FFFF                                                                     [100%]
=================================== FAILURES ===================================
______ test_health_budget_covers_existing_eight_second_dependency_probes _______

    def test_health_budget_covers_existing_eight_second_dependency_probes():
        def endpoint(_request, timeout):
            if timeout < 8:
                raise TimeoutError("dependency snapshot still running")
            return Response({"services": [{"name": "api", "ok": True}], "all_ok": True})
>       assert doctor._health_probe("reader", opener=endpoint)["status"] == "healthy_http"
E       AssertionError: assert 'local_timeout' == 'healthy_http'
E         
E         - healthy_http
E         + local_timeout

scripts/tests/bin/test_webhook_doctor.py:440: AssertionError
________ test_health_timeout_with_listener_is_inconclusive_not_restart _________

monkeypatch = <_pytest.monkeypatch.MonkeyPatch object at 0x10b0d8640>
tmp_path = PosixPath('/private/tmp/pytest-of-cliang/pytest-1889/test_health_timeout_with_liste0')

    def test_health_timeout_with_listener_is_inconclusive_not_restart(monkeypatch, tmp_path):
        _stub_local_facts(monkeypatch, tmp_path)
        monkeypatch.setenv("K3DM_WEBHOOK_TOKEN_READER", "reader")
        monkeypatch.setattr(doctor, "_health_probe", lambda *_args, **_kwargs: {"status": "local_timeout", "http_responsive": False, "all_ok": None})
        result = doctor.diagnose(check=True)
>       assert result["classification"] == "health_check_timeout"
E       AssertionError: assert 'local_http_unresponsive' == 'health_check_timeout'
E         
E         - health_check_timeout
E         + local_http_unresponsive

scripts/tests/bin/test_webhook_doctor.py:448: AssertionError
__________ test_confirmed_missing_listener_remains_recovery_evidence ___________

monkeypatch = <_pytest.monkeypatch.MonkeyPatch object at 0x10b9c1370>
tmp_path = PosixPath('/private/tmp/pytest-of-cliang/pytest-1889/test_confirmed_missing_listene0')

    def test_confirmed_missing_listener_remains_recovery_evidence(monkeypatch, tmp_path):
        _stub_local_facts(monkeypatch, tmp_path)
        monkeypatch.setenv("K3DM_WEBHOOK_TOKEN_READER", "reader")
        monkeypatch.setattr(doctor, "_listener_facts", lambda **_kwargs: {"status": "no_listener", "listening": False})
        monkeypatch.setattr(doctor, "_health_probe", lambda *_args, **_kwargs: {"status": "local_timeout", "http_responsive": False, "all_ok": None})
        result = doctor.diagnose(check=True)
>       assert result["classification"] == "listener_missing"
E       AssertionError: assert 'local_http_unresponsive' == 'listener_missing'
E         
E         - listener_missing
E         + local_http_unresponsive

scripts/tests/bin/test_webhook_doctor.py:463: AssertionError
________________ test_health_header_and_body_share_one_deadline ________________

monkeypatch = <_pytest.monkeypatch.MonkeyPatch object at 0x10b13e7a0>

    def test_health_header_and_body_share_one_deadline(monkeypatch):
        ticks = iter((100.0, 107.0))
        monkeypatch.setattr(doctor.time, "monotonic", lambda: next(ticks))
        remaining = []
        def body(_response, timeout):
            remaining.append(timeout)
            return b'{"services":[{"name":"api","ok":true}],"all_ok":true}'
        monkeypatch.setattr(doctor, "_read_health_body", body)
        result = doctor._health_probe("reader", timeout=10, opener=lambda *_args, **_kwargs: Response({}))
        assert result["status"] == "healthy_http"
>       assert remaining == [3.0]
E       assert [10] == [3.0]
E         
E         At index 0 diff: 10 != 3.0
E         Use -v to get more diff

scripts/tests/bin/test_webhook_doctor.py:478: AssertionError
=========================== short test summary info ============================
FAILED scripts/tests/bin/test_webhook_doctor.py::test_health_budget_covers_existing_eight_second_dependency_probes
FAILED scripts/tests/bin/test_webhook_doctor.py::test_health_timeout_with_listener_is_inconclusive_not_restart
FAILED scripts/tests/bin/test_webhook_doctor.py::test_confirmed_missing_listener_remains_recovery_evidence
FAILED scripts/tests/bin/test_webhook_doctor.py::test_health_header_and_body_share_one_deadline
4 failed, 31 deselected in 0.25s
```

## Actual final offline gates

```text
...................................                                      [100%]
35 passed in 0.67s
1..5
ok 1 restart-webhook reloads the plist with bootout then bootstrap, never kickstarting the webhook
ok 2 restart-webhook continues to bootstrap when bootout reports the job is not loaded
ok 3 restart-webhook still restarts the cloud bridge
ok 4 restart-webhook retries bootstrap twice then reports success
ok 5 restart-webhook fails after five bootstrap attempts and skips cloud bridge
All checks passed!
```

Ruff/diff check, staged lint/audit and normal checkpoint hooks passed. The
existing legitimate assertion-replacement explanation was updated for the
production-aligned health budget. No hook bypass, no live credential change.
No production shell was changed, so ShellCheck is not applicable. Existing
whole-suite failures remain separately recorded; full suite was not repeated.

## Current corrected direct live result

```json
{"classification": "local_http_healthy_external_delivery_unverified", "credential": {"lookup_exit": 0, "source": "keychain", "status": "available"}, "credential_action": null, "health": {"all_ok": true, "http_responsive": true, "status": "healthy_http"}, "health_timeout_seconds": 15, "launchd": {"last_exit_code": null, "pid": 4295, "port": 7443, "status": "loaded"}, "listener": {"listening": true, "status": "listening"}, "log": {"available": true, "error_categories": ["exception"], "freshness": "fresh", "modified_utc": "2026-10-27T22:48:14.440360+00:00"}, "mode": "check", "process": {"pids": [4295], "status": "available"}, "recovery_action": null, "recovery_recommended": false, "timestamp_utc": "2026-10-27T22:49:14.578317+00:00"}
```

Current authenticated health is good with no recovery warranted/performed.
Recent exception log category is contextual; successful functional response
is not negated by a category alone. This is a coordinator direct check, not
represented as reading the operator's pane or reproducing the exact prior
request. The historical offsite incident cause remains unknown; prior
operator Slack job a13d5831 remains end-to-end evidence.

Resume queued GHCR runtime verification once no concurrent scanner is active.
Deployment image/init/non-root/script-hash prerequisites already passed.
A manual make app-cve-scan is an existing real scan and may promote clean
candidates; it must be operator-run, with output reviewed before advancing.
No manual scan has been triggered by coordinator. Heartbeats/coordinator E3
remain queued after that item.
