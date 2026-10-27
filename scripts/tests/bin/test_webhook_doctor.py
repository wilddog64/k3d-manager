# agent-audit: allow assert-removed replace incorrect port 9000 with server port 7443 and retain redaction checks with validated loaded port
import importlib.util
import io
from importlib.machinery import SourceFileLoader
import json
import subprocess
import sys
import time
import urllib.error
import urllib.response
import urllib.request
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[3] / "bin" / "k3dm-webhook-doctor"
SPEC = importlib.util.spec_from_loader("webhook_doctor", SourceFileLoader("webhook_doctor", str(MODULE_PATH)))
doctor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(doctor)


class Response:
    status = 200

    def __init__(self, payload):
        self.payload = json.dumps(payload).encode()
        self.offset = 0

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self, _limit):
        chunk = self.payload[self.offset:self.offset + _limit]
        self.offset += len(chunk)
        return chunk


def test_dry_run_has_plan_without_subprocess(monkeypatch):
    monkeypatch.setattr(doctor, "_run", lambda *_a, **_k: (_ for _ in ()).throw(AssertionError("subprocess")))
    monkeypatch.setattr(doctor, "_keychain_reader_credential", lambda: (_ for _ in ()).throw(AssertionError("secret read")))
    monkeypatch.setattr(doctor, "_log_facts", lambda *_a: (_ for _ in ()).throw(AssertionError("log access")))
    monkeypatch.setattr(doctor, "_health_probe", lambda *_a: (_ for _ in ()).throw(AssertionError("network")))
    monkeypatch.setattr(doctor.Path, "home", lambda: (_ for _ in ()).throw(AssertionError("home access")))
    result = doctor.diagnose()
    assert result["mode"] == "dry-run"
    assert "reader-authenticated loopback /api/v1/health?quick=1" in result["probes"]


def test_health_probe_keeps_handler_and_dependency_health_separate():
    seen = {}

    def probe(request, timeout):
        seen["url"] = request.full_url
        seen["authorization"] = request.get_header("Authorization")
        seen["timeout"] = timeout
        return Response({"services": [{"name": "slack", "ok": False}], "all_ok": False})

    result = doctor._health_probe("reader-secret", opener=probe)
    assert result == {"status": "healthy_http_services_degraded", "http_responsive": True, "all_ok": False}
    assert seen == {"url": "http://127.0.0.1:7443/api/v1/health?quick=1",
                    "authorization": "Bearer reader-secret", "timeout": doctor.TIMEOUT}


def test_health_transport_blocks_redirects_and_proxy_routes():
    opener = doctor._build_health_opener()
    redirect = next(handler for handler in opener.handlers if isinstance(handler, doctor._NoRedirectHandler))
    assert redirect.redirect_request(None, None, 302, "found", {}, "http://evil.invalid/") is None
    assert not any(isinstance(handler, urllib.request.ProxyHandler) for handler in opener.handlers)


def test_health_opener_does_not_forward_credentials_after_redirect(monkeypatch):
    calls = []

    class FakeHTTPHandler(urllib.request.HTTPHandler):
        def http_open(self, request):
            calls.append((request.full_url, request.get_header("Authorization")))
            if len(calls) == 1:
                response = urllib.response.addinfourl(
                    io.BytesIO(b""), {"Location": "http://attacker.invalid/collect"}, request.full_url, 302)
                response.msg = "Found"
                return response
            raise AssertionError("redirect target was contacted")

    opener = doctor._build_health_opener(extra_handlers=(FakeHTTPHandler(),))
    result = doctor._health_probe("reader-secret", opener=opener.open)
    assert result["status"] == "http_error"
    assert calls == [("http://127.0.0.1:7443/api/v1/health?quick=1", "Bearer reader-secret")]


def test_command_capture_is_bounded():
    result = doctor._run([sys.executable, "-c", "print('x' * 1000000)"])
    assert len(result["stdout"]) <= doctor.COMMAND_OUTPUT_LIMIT
    assert result["output_limited"] is True


def test_timeout_and_auth_are_distinct():
    def timeout(_request, timeout):
        raise TimeoutError()

    def denied(_request, timeout):
        raise urllib.error.HTTPError("local", 401, "denied", {}, None)

    assert doctor._health_probe("x", opener=timeout)["status"] == "local_timeout"
    assert doctor._health_probe("x", opener=denied)["status"] == "auth_failed"


def test_health_schema_is_validated():
    response = lambda _request, timeout: Response({"all_ok": True, "services": "bad"})
    assert doctor._health_probe("x", opener=response)["status"] == "invalid_response"


def test_health_schema_rejects_service_row_without_ok():
    response = lambda _request, timeout: Response({"all_ok": True, "services": [{"name": "api"}]})
    assert doctor._health_probe("x", opener=response)["status"] == "invalid_response"


def test_health_schema_accepts_unknown_ok_but_not_contradictions_or_empty():
    unknown = lambda _request, timeout: Response({"all_ok": True, "services": [{"name": "optional", "ok": None}]})
    contradictory = lambda _request, timeout: Response({"all_ok": True, "services": [{"name": "api", "ok": False}]})
    degraded_conflict = lambda _request, timeout: Response({"all_ok": False, "services": [{"name": "api", "ok": True}]})
    empty = lambda _request, timeout: Response({"all_ok": True, "services": []})
    assert doctor._health_probe("x", opener=unknown)["status"] == "healthy_http_dependencies_unknown"
    assert doctor._health_probe("x", opener=contradictory)["status"] == "invalid_response"
    assert doctor._health_probe("x", opener=degraded_conflict)["status"] == "invalid_response"
    assert doctor._health_probe("x", opener=empty)["status"] == "healthy_http_dependencies_unknown"


def test_health_body_has_total_deadline():
    class SlowResponse(Response):
        def read(self, limit):
            time.sleep(0.02)
            return super().read(limit)

    try:
        doctor._read_health_body(SlowResponse({"services": [], "all_ok": True}), 0.005)
    except TimeoutError:
        pass
    else:
        raise AssertionError("response exceeded the total deadline")


def test_classification_keeps_handler_errors_distinct(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_WEBHOOK_TOKEN_READER", "reader")
    monkeypatch.setattr(doctor.os, "getuid", lambda: 501)
    monkeypatch.setattr(doctor, "_launchd_facts", lambda _uid: {"status": "loaded", "pid": 42, "last_exit_code": 0})
    monkeypatch.setattr(doctor, "_process_facts", lambda **_kwargs: {"status": "available", "pids": [42]})
    monkeypatch.setattr(doctor, "_listener_facts", lambda **_kwargs: {"status": "listening", "listening": True})
    monkeypatch.setattr(doctor, "_log_facts", lambda _path: {})
    for status in ("invalid_response", "http_error"):
        monkeypatch.setattr(doctor, "_health_probe", lambda _token, status=status, **_kwargs: {"status": status, "http_responsive": True, "all_ok": None})
        result = doctor.diagnose(check=True)
        assert result["classification"] == status
        assert result["recovery_recommended"] is False


def test_launchd_facts_do_not_return_environment_or_raw_output():
    def runner(_argv, timeout=doctor.TIMEOUT):
        return subprocess.CompletedProcess([], 0, "pid = 123\nlast exit code = 0\nK3DM_WEBHOOK_TOKEN=secret\n", "")

    facts = doctor._launchd_facts("501", runner=runner)
    assert facts == {"status": "loaded", "pid": 123, "last_exit_code": 0, "port": 7443}
    assert "secret" not in json.dumps(facts)


def test_log_summary_is_bounded_and_redacts_contents(tmp_path):
    path = tmp_path / "webhook.log"
    path.write_text("Authorization: Bearer secret\nTraceback: failure\n")
    facts = doctor._log_facts(path)
    assert facts["available"] is True
    assert facts["error_categories"] == ["exception"]
    assert "secret" not in json.dumps(facts)


def test_classification_preserves_listener_and_recovery_policy(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_WEBHOOK_TOKEN_READER", "reader")
    monkeypatch.setattr(doctor.os, "getuid", lambda: 501)
    monkeypatch.setattr(doctor, "_launchd_facts", lambda _uid: {"status": "loaded", "pid": 42, "last_exit_code": 0})
    monkeypatch.setattr(doctor, "_process_facts", lambda **_kwargs: {"status": "available", "pids": [42]})
    monkeypatch.setattr(doctor, "_listener_facts", lambda **_kwargs: {"status": "listening", "listening": True})
    monkeypatch.setattr(doctor, "_log_facts", lambda _path: {"available": False, "modified_utc": None, "freshness": "missing", "error_categories": []})
    monkeypatch.setattr(doctor, "_health_probe", lambda _token, **_kwargs: {"status": "healthy_http_services_degraded", "http_responsive": True, "all_ok": False})
    result = doctor.diagnose(check=True)
    assert result["classification"] == "local_http_handler_responsive_dependencies_degraded"
    assert result["recovery_recommended"] is False
    assert "restart" not in result["classification"]


def test_diagnostic_never_calls_recovery(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_WEBHOOK_TOKEN_READER", "reader")
    monkeypatch.setattr(doctor.os, "getuid", lambda: 501)
    monkeypatch.setattr(doctor, "_launchd_facts", lambda _uid: {"status": "missing", "pid": None, "last_exit_code": None})
    monkeypatch.setattr(doctor, "_process_facts", lambda **_kwargs: {"status": "available", "pids": []})
    monkeypatch.setattr(doctor, "_listener_facts", lambda **_kwargs: {"status": "no_listener", "listening": False})
    monkeypatch.setattr(doctor, "_log_facts", lambda _path: {"available": False, "modified_utc": None, "freshness": "missing", "error_categories": []})
    monkeypatch.setattr(doctor, "_health_probe", lambda _token, **_kwargs: {"status": "local_timeout", "http_responsive": False, "all_ok": None})
    result = doctor.diagnose(check=True)
    assert result["recovery_recommended"] is True
    assert "make restart-webhook" in result["recovery_action"]
    assert "restart-webhook" not in doctor.LABEL


def test_diagnostic_command_and_listener_failures_are_not_missing_or_restart(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.delenv("K3DM_WEBHOOK_TOKEN_READER", raising=False)
    monkeypatch.setattr(doctor.os, "getuid", lambda: 501)
    monkeypatch.setattr(doctor, "_launchd_facts", lambda _uid: {"status": "permission_error", "pid": None, "last_exit_code": None})
    monkeypatch.setattr(doctor, "_process_facts", lambda **_kwargs: {"status": "unavailable", "pids": []})
    monkeypatch.setattr(doctor, "_listener_facts", lambda **_kwargs: {"status": "command_error", "listening": None})
    monkeypatch.setattr(doctor, "_log_facts", lambda _path: {})
    monkeypatch.setattr(doctor, "_keychain_reader_credential", lambda: (None, {"source": "keychain", "status": "missing"}))
    result = doctor.diagnose(check=True)
    assert result["classification"] == "launchd_permission_error"
    assert result["recovery_recommended"] is False
    assert result["health"]["status"] == "auth_unavailable"


def test_launchd_and_listener_command_outcomes_are_distinguished():
    unavailable = lambda *_a, **_k: None
    timed_out = lambda *_a, **_k: {"timed_out": True}
    missing = lambda *_a, **_k: subprocess.CompletedProcess([], 113, "", "Could not find service")
    unknown = lambda *_a, **_k: subprocess.CompletedProcess([], 1, "", "Operation not permitted")
    assert doctor._launchd_facts("501", runner=unavailable)["status"] == "command_unavailable"
    assert doctor._launchd_facts("501", runner=timed_out)["status"] == "command_timeout"
    assert doctor._launchd_facts("501", runner=missing)["status"] == "missing"
    assert doctor._launchd_facts("501", runner=unknown)["status"] == "command_error"
    assert doctor._listener_facts(runner=unknown)["status"] == "command_error"


def test_keychain_reader_token_uses_bounded_command_dict_contract(monkeypatch):
    result = {"returncode": 0, "stdout": "fixture-reader-token\n", "timed_out": False, "output_limited": False}
    monkeypatch.setattr(doctor, "_run", lambda _args: result)
    assert doctor._keychain_reader_token() == "fixture-reader-token"


def test_keychain_reader_token_returns_none_for_missing_timeout_and_truncation(monkeypatch):
    cases = (
        {"returncode": 44, "stdout": "", "timed_out": False, "output_limited": False},
        {"returncode": -15, "stdout": "partial-reader-token", "timed_out": True, "output_limited": False},
        {"returncode": -15, "stdout": "partial-reader-token", "timed_out": False, "output_limited": True},
    )
    for result in cases:
        monkeypatch.setattr(doctor, "_run", lambda _args, result=result: result)
        assert doctor._keychain_reader_token() is None


def test_diagnose_uses_reader_token_from_mocked_dict_command_when_env_absent(monkeypatch, tmp_path):
    monkeypatch.delenv("K3DM_WEBHOOK_TOKEN_READER", raising=False)
    monkeypatch.setenv("HOME", str(tmp_path))
    calls = []

    def run(argv):
        calls.append(argv)
        return {"returncode": 0, "stdout": "fixture-reader-token\n",
                "timed_out": False, "output_limited": False}

    monkeypatch.setattr(doctor, "_run", run)
    monkeypatch.setattr(doctor.os, "getuid", lambda: 501)
    monkeypatch.setattr(doctor, "_launchd_facts", lambda _uid: {"status": "loaded", "pid": 42, "last_exit_code": 0})
    monkeypatch.setattr(doctor, "_process_facts", lambda **_kwargs: {"status": "available", "pids": [42]})
    monkeypatch.setattr(doctor, "_listener_facts", lambda **_kwargs: {"status": "listening", "listening": True})
    monkeypatch.setattr(doctor, "_log_facts", lambda _path: {})
    monkeypatch.setattr(doctor, "_health_probe", lambda token, **_kwargs: {"status": "healthy_http", "http_responsive": True, "all_ok": True}
                        if token == "fixture-reader-token" else (_ for _ in ()).throw(AssertionError("token missing")))
    result = doctor.diagnose(check=True)
    assert result["classification"] == "local_http_healthy_external_delivery_unverified"
    assert calls == [["security", "find-generic-password", "-s", "k3dm-webhook-token-reader", "-a", "k3dm", "-w"]]


def test_check_and_dry_run_conflict_is_rejected_without_io(monkeypatch):
    monkeypatch.setattr(doctor, "diagnose", lambda **_kwargs: (_ for _ in ()).throw(AssertionError("I/O")))
    try:
        doctor.main(["--check", "--dry-run"])
    except SystemExit as exc:
        assert exc.code == 2
    else:
        raise AssertionError("conflicting modes accepted")


def test_loaded_webhook_port_is_used_for_listener_and_health(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_WEBHOOK_TOKEN_READER", "reader")
    monkeypatch.setattr(doctor, "_launchd_facts", lambda _uid: {"status": "loaded", "pid": 42, "port": 8555})
    monkeypatch.setattr(doctor, "_process_facts", lambda: {"status": "available", "pids": [42]})
    monkeypatch.setattr(doctor, "_log_facts", lambda _path: {})
    ports = []
    def listener(**kwargs):
        ports.append(kwargs["port"])
        return {"status": "listening", "listening": True}
    def health(_token, **kwargs):
        ports.append(kwargs["port"])
        return {"status": "healthy_http", "http_responsive": True, "all_ok": True}
    monkeypatch.setattr(doctor, "_listener_facts", listener)
    monkeypatch.setattr(doctor, "_health_probe", health)
    result = doctor.diagnose(check=True)
    assert ports == [8555, 8555]
    assert result["recovery_recommended"] is False


def test_launchd_port_defaults_to_server_and_validates_override():
    def facts(output):
        return doctor._launchd_facts(501, runner=lambda _args: subprocess.CompletedProcess([], 0, output, ""))
    assert facts("pid = 42\n")["port"] == 7443
    assert facts("pid = 42\n K3DM_WEBHOOK_PORT => 8555\n")["port"] == 8555
    for invalid in ("0", "65536", "invalid-secret-value"):
        value = facts(f"pid = 42\n K3DM_WEBHOOK_PORT => {invalid}\n")
        assert value["port"] is None
        assert invalid not in json.dumps(value)
    assert doctor._health_probe("reader", port=None)["status"] == "configuration_unavailable"
    assert doctor._listener_facts(port=None)["listening"] is None


def test_doctor_default_port_matches_production_webhook(monkeypatch):
    import runpy
    monkeypatch.delenv("K3DM_WEBHOOK_PORT", raising=False)
    config = MODULE_PATH.parents[1] / "scripts/lib/webhook/config.py"
    assert doctor.PORT == runpy.run_path(str(config))["PORT"]


def test_command_waits_for_success_after_output_streams_close():
    result = doctor._run([sys.executable, "-c",
        "import os,time;os.write(1,b'fixture-reader-token\\n');os.close(1);os.close(2);time.sleep(.1)"])
    assert result["returncode"] == 0
    assert result["stdout"] == "fixture-reader-token\n"
    assert result["timed_out"] is False


def test_command_with_closed_streams_still_obeys_deadline():
    result = doctor._run([sys.executable, "-c",
        "import os,time;os.close(1);os.close(2);time.sleep(5)"], timeout=0.1)
    assert result["timed_out"] is True
    assert result["returncode"] != 0


def _stub_local_facts(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.delenv("K3DM_WEBHOOK_TOKEN_READER", raising=False)
    monkeypatch.setattr(doctor, "_launchd_facts", lambda _uid: {"status": "loaded", "pid": 42, "port": 7443})
    monkeypatch.setattr(doctor, "_process_facts", lambda: {"status": "available", "pids": [42]})
    monkeypatch.setattr(doctor, "_listener_facts", lambda **_kwargs: {"status": "listening", "listening": True})
    monkeypatch.setattr(doctor, "_log_facts", lambda _path: {})
    monkeypatch.setattr(doctor, "_build_health_opener", lambda: (_ for _ in ()).throw(AssertionError("HTTP must not run")))


def test_locked_keychain_reports_access_action_without_http_or_restart(monkeypatch, tmp_path):
    _stub_local_facts(monkeypatch, tmp_path)
    calls = []
    def lookup(argv):
        calls.append(argv)
        return {"returncode": 36, "stdout": "User interaction is not allowed. private-fixture-value",
                "timed_out": False, "output_limited": False}
    monkeypatch.setattr(doctor, "_run", lookup)
    result = doctor.diagnose(check=True)
    assert result["classification"] == "keychain_interaction_required"
    assert result["credential"]["status"] == "interaction_required"
    assert result["health"]["status"] == "auth_unavailable"
    assert result["health"]["http_responsive"] is False
    assert "security unlock-keychain" in result["credential_action"]
    assert result["recovery_recommended"] is False
    assert result["recovery_action"] is None
    assert "private-fixture-value" not in json.dumps(result)
    assert len(calls) == 1 and calls[0][1] == "find-generic-password"


def test_missing_reader_is_distinct_from_keychain_access_block(monkeypatch, tmp_path):
    _stub_local_facts(monkeypatch, tmp_path)
    monkeypatch.setattr(doctor, "_run", lambda _args: {"returncode": 44, "stdout": "item missing private-fixture-value"})
    result = doctor.diagnose(check=True)
    assert result["classification"] == "auth_unavailable"
    assert result["credential"]["status"] == "missing"
    assert "k3dm-webhook-token-reader" in result["credential_action"]
    assert "unlock-keychain" not in result["credential_action"]
    assert result["recovery_recommended"] is False
    assert result["recovery_action"] is None
    assert "private-fixture-value" not in json.dumps(result)


def test_keychain_statuses_are_bounded_and_never_return_partial_credentials(monkeypatch):
    cases = [
        (None, "command_unavailable"),
        ({"returncode": -15, "stdout": "private", "timed_out": True}, "command_timeout"),
        ({"returncode": -15, "stdout": "private", "output_limited": True}, "command_output_limit"),
        ({"returncode": 51, "stdout": "private"}, "lookup_failed"),
        ({"returncode": 0, "stdout": ""}, "empty"),
    ]
    for command, expected in cases:
        monkeypatch.setattr(doctor, "_run", lambda _args, command=command: command)
        token, facts = doctor._keychain_reader_credential()
        assert token is None
        assert facts["status"] == expected
        assert "private" not in json.dumps(facts)


def test_reader_environment_bypasses_keychain_and_is_not_exposed(monkeypatch, tmp_path):
    _stub_local_facts(monkeypatch, tmp_path)
    monkeypatch.setenv("K3DM_WEBHOOK_TOKEN_READER", "private-env-fixture")
    monkeypatch.setattr(doctor, "_run", lambda *_args: (_ for _ in ()).throw(AssertionError("Keychain lookup")))
    monkeypatch.setattr(doctor, "_health_probe", lambda token, **_kwargs: {"status": "healthy_http", "http_responsive": True, "all_ok": True})
    result = doctor.diagnose(check=True)
    assert result["credential"] == {"source": "environment", "status": "available"}
    assert result["credential_action"] is None
    assert result["classification"] == "local_http_healthy_external_delivery_unverified"
    assert "private-env-fixture" not in json.dumps(result)


def test_keychain_unlock_is_observed_on_next_check_without_cached_token(monkeypatch, tmp_path):
    _stub_local_facts(monkeypatch, tmp_path)
    command = {"returncode": 36, "stdout": "User interaction is not allowed."}
    calls = []
    def lookup(argv):
        calls.append(argv)
        return command.copy()
    def health(token, **_kwargs):
        return {"status": "healthy_http" if token else "auth_unavailable",
                "http_responsive": bool(token), "all_ok": True if token else None}
    monkeypatch.setattr(doctor, "_run", lookup)
    monkeypatch.setattr(doctor, "_health_probe", health)
    locked = doctor.diagnose(check=True)
    command.update(returncode=0, stdout="private-unlocked-fixture\n")
    unlocked = doctor.diagnose(check=True)
    assert locked["classification"] == "keychain_interaction_required"
    assert unlocked["classification"] == "local_http_healthy_external_delivery_unverified"
    assert unlocked["credential"]["status"] == "available"
    assert unlocked["credential_action"] is None
    assert not locked["recovery_recommended"] and not unlocked["recovery_recommended"]
    assert locked["recovery_action"] is None and unlocked["recovery_action"] is None
    assert len(calls) == 2 and all(argv[1] == "find-generic-password" for argv in calls)
    assert "private-unlocked-fixture" not in json.dumps(unlocked)
