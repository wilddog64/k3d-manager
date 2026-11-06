"""Request access log attribution and redaction coverage."""

import importlib.util
import os
import sys
import threading
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import SimpleNamespace

import pytest


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
_WEBHOOK = Path(os.environ.get("K3DM_TEST_WEBHOOK_FILE", ROOT / "bin" / "k3dm-webhook"))
_SPEC = importlib.util.spec_from_file_location(
    "k3dm_webhook_access_log", _WEBHOOK,
    loader=SourceFileLoader("k3dm_webhook_access_log", str(_WEBHOOK)),
)
wh = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(wh)


@pytest.fixture
def local_server(monkeypatch, tmp_path):
    scratch_home = tmp_path / "home"
    scratch_home.mkdir()
    jobs = tmp_path / "jobs"
    run = tmp_path / "run"
    jobs.mkdir()
    run.mkdir()
    monkeypatch.setenv("HOME", str(scratch_home))
    monkeypatch.setattr(wh, "JOB_DIR", jobs)
    monkeypatch.setattr(wh, "RUN_DIR", run)
    assert Path(os.environ["HOME"]) == scratch_home
    assert wh.JOB_DIR == jobs and wh.RUN_DIR == run

    records = []
    monkeypatch.setattr(wh._LOG, "info", lambda fmt, *args: records.append((fmt, args)))
    server = ThreadingHTTPServer(("127.0.0.1", 0), wh._Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server, records
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


def _get(server, headers=None):
    request = urllib.request.Request(
        f"http://127.0.0.1:{server.server_port}/", headers=headers or {}
    )
    try:
        return urllib.request.urlopen(request, timeout=2)
    except urllib.error.HTTPError as error:
        return error


def _line(record):
    fmt, args = record
    return fmt % args


def test_client_ip_and_local_fallback_are_logged(local_server):
    server, records = local_server
    assert _get(server, {"CF-Connecting-IP": "203.0.113.7"}).code == 401
    assert "client=203.0.113.7" in _line(records[-1])
    assert _get(server).code == 401
    assert "client=local" in _line(records[-1])


def test_user_agent_is_sanitized_and_truncated(local_server):
    server, records = local_server
    ua = "Probe/1.0 " + "x" * 90
    assert _get(server, {"User-Agent": ua}).code == 401
    line = _line(records[-1])
    logged = line.split(' ua="', 1)[1][:-1]
    assert logged == ua[:80]
    assert len(logged) == 80


def test_absent_user_agent_uses_dash(local_server):
    _server, records = local_server
    handler = SimpleNamespace(
        headers={}, path="/", command="GET", _response_code=401,
        _token_role="unknown", _request_started=wh.time.monotonic(),
    )
    wh._Handler.log_message(handler, "")
    assert 'ua="-"' in _line(records[-1])


def test_existing_fields_keep_order_and_secrets_never_log(local_server):
    server, records = local_server
    secret = "synthetic-secret-token"
    request = urllib.request.Request(
        f"http://127.0.0.1:{server.server_port}/?query=synthetic-query",
        data=b"synthetic-body", headers={"Authorization": f"Bearer {secret}"}, method="POST",
    )
    try:
        urllib.request.urlopen(request, timeout=2)
    except urllib.error.HTTPError:
        pass
    line = _line(records[-1])
    keys = ["method=", "path=", "status=", "role=", "duration_ms=", "client=", "ua="]
    assert [line.index(key) for key in keys] == sorted(line.index(key) for key in keys)
    assert "method=POST" in line and "path=/" in line and "status=401" in line
    assert "role=None" in line and "duration_ms=" in line
    assert secret not in line and "synthetic-query" not in line and "synthetic-body" not in line


@pytest.mark.parametrize("header,value", [
    ("CF-Connecting-IP", "203.0.113.7\nrole=admin"),
    ("User-Agent", 'Probe" status=200\nforged=yes'),
])
def test_untrusted_header_controls_cannot_forge_fields(local_server, header, value):
    _server, records = local_server
    handler = SimpleNamespace(
        headers={header: value}, path="/", command="GET", _response_code=401,
        _token_role="reader", _request_started=wh.time.monotonic(),
    )
    wh._Handler.log_message(handler, "")
    line = _line(records[-1])
    assert "\n" not in line and "\r" not in line and '" status' not in line
    assert "role=admin" not in line and "status=200" not in line
    if header == "CF-Connecting-IP":
        assert "client=invalid" in line
    else:
        assert 'ua="Probe_ status_200_forged_yes"' in line


def test_get_root_without_credentials_remains_unauthorized(local_server, monkeypatch):
    server, _records = local_server
    assert _get(server).code == 401
    monkeypatch.setattr(wh, "_resolve_token_role", lambda _token: "reader")
    monkeypatch.setattr(wh, "_get_token", lambda: "")
    monkeypatch.setattr(wh, "_get_reader_token", lambda: "")
    monkeypatch.setattr(wh, "_get_cloud_runner_token", lambda: "")
    monkeypatch.setattr(wh, "_register_secret", lambda _secret: None)
    assert _get(server, {"Authorization": "Bearer test-token"}).code == 404
