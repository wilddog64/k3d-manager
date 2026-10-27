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
    monkeypatch.setattr(doctor, "_keychain_reader_token", lambda: (_ for _ in ()).throw(AssertionError("secret read")))
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
    assert seen == {"url": "http://127.0.0.1:9000/api/v1/health?quick=1",
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
    assert calls == [("http://127.0.0.1:9000/api/v1/health?quick=1", "Bearer reader-secret")]


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
    monkeypatch.setattr(doctor, "_process_facts", lambda: {"status": "available", "pids": [42]})
    monkeypatch.setattr(doctor, "_listener_facts", lambda: {"status": "listening", "listening": True})
    monkeypatch.setattr(doctor, "_log_facts", lambda _path: {})
    for status in ("invalid_response", "http_error"):
        monkeypatch.setattr(doctor, "_health_probe", lambda _token, status=status: {"status": status, "http_responsive": True, "all_ok": None})
        result = doctor.diagnose(check=True)
        assert result["classification"] == status
        assert result["recovery_recommended"] is False


def test_launchd_facts_do_not_return_environment_or_raw_output():
    def runner(_argv, timeout=doctor.TIMEOUT):
        return subprocess.CompletedProcess([], 0, "pid = 123\nlast exit code = 0\nK3DM_WEBHOOK_TOKEN=secret\n", "")

    facts = doctor._launchd_facts("501", runner=runner)
    assert facts == {"status": "loaded", "pid": 123, "last_exit_code": 0}
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
    monkeypatch.setattr(doctor, "_process_facts", lambda: {"status": "available", "pids": [42]})
    monkeypatch.setattr(doctor, "_listener_facts", lambda: {"status": "listening", "listening": True})
    monkeypatch.setattr(doctor, "_log_facts", lambda _path: {"available": False, "modified_utc": None, "freshness": "missing", "error_categories": []})
    monkeypatch.setattr(doctor, "_health_probe", lambda _token: {"status": "healthy_http_services_degraded", "http_responsive": True, "all_ok": False})
    result = doctor.diagnose(check=True)
    assert result["classification"] == "local_http_handler_responsive_dependencies_degraded"
    assert result["recovery_recommended"] is False
    assert "restart" not in result["classification"]


def test_diagnostic_never_calls_recovery(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_WEBHOOK_TOKEN_READER", "reader")
    monkeypatch.setattr(doctor.os, "getuid", lambda: 501)
    monkeypatch.setattr(doctor, "_launchd_facts", lambda _uid: {"status": "missing", "pid": None, "last_exit_code": None})
    monkeypatch.setattr(doctor, "_process_facts", lambda: {"status": "available", "pids": []})
    monkeypatch.setattr(doctor, "_listener_facts", lambda: {"status": "no_listener", "listening": False})
    monkeypatch.setattr(doctor, "_log_facts", lambda _path: {"available": False, "modified_utc": None, "freshness": "missing", "error_categories": []})
    monkeypatch.setattr(doctor, "_health_probe", lambda _token: {"status": "local_timeout", "http_responsive": False, "all_ok": None})
    result = doctor.diagnose(check=True)
    assert result["recovery_recommended"] is True
    assert "make restart-webhook" in result["recovery_action"]
    assert "restart-webhook" not in doctor.LABEL


def test_diagnostic_command_and_listener_failures_are_not_missing_or_restart(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.delenv("K3DM_WEBHOOK_TOKEN_READER", raising=False)
    monkeypatch.setattr(doctor.os, "getuid", lambda: 501)
    monkeypatch.setattr(doctor, "_launchd_facts", lambda _uid: {"status": "permission_error", "pid": None, "last_exit_code": None})
    monkeypatch.setattr(doctor, "_process_facts", lambda: {"status": "unavailable", "pids": []})
    monkeypatch.setattr(doctor, "_listener_facts", lambda: {"status": "command_error", "listening": None})
    monkeypatch.setattr(doctor, "_log_facts", lambda _path: {})
    monkeypatch.setattr(doctor, "_keychain_reader_token", lambda: None)
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
    monkeypatch.setattr(doctor, "_process_facts", lambda: {"status": "available", "pids": [42]})
    monkeypatch.setattr(doctor, "_listener_facts", lambda: {"status": "listening", "listening": True})
    monkeypatch.setattr(doctor, "_log_facts", lambda _path: {})
    monkeypatch.setattr(doctor, "_health_probe", lambda token: {"status": "healthy_http", "http_responsive": True, "all_ok": True}
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
