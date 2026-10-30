"""Offline behavior tests: all HTTP transports and sockets are injected."""
import builtins
import importlib.util
import io
import json
import os
import socket
import ssl
import subprocess
import urllib.request
import urllib.response
from email.message import Message
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import pytest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "bin/k3dm-cloudflare-posture"
spec = importlib.util.spec_from_loader("cloudflare_posture", SourceFileLoader("cloudflare_posture", str(SCRIPT)))
posture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(posture)
ZONE = "a" * 32
SECRET = "sentinel-secret-value"
VERSIONS = {"1.0": (ssl.TLSVersion.TLSv1, "TLSv1"), "1.1": (ssl.TLSVersion.TLSv1_1, "TLSv1.1"),
            "1.2": (ssl.TLSVersion.TLSv1_2, "TLSv1.2"), "1.3": (ssl.TLSVersion.TLSv1_3, "TLSv1.3")}


def forbidden(*args, **kwargs):
    raise AssertionError("unexpected environment, credential, filesystem, process, or network access")


@pytest.fixture(autouse=True)
def no_live_sockets(monkeypatch):
    monkeypatch.setattr(socket, "create_connection", forbidden)
    monkeypatch.setattr(socket, "socket", forbidden)
    monkeypatch.setattr(urllib.request, "urlopen", forbidden)


class NoEnvironment:
    get = __getitem__ = __iter__ = __contains__ = forbidden


class Body(io.BytesIO):
    def __init__(self, data, readable):
        super().__init__(data)
        self.readable_body = readable
        self.read_sizes = []

    def read(self, size=-1):
        assert self.readable_body, "response/error body must not be read"
        assert size == posture.MAX_BYTES + 1, "body reads must have a fixed bound"
        self.read_sizes.append(size)
        return super().read(size)


def install_transport(monkeypatch, responder):
    """Exercise the real urllib opener, redirect handler, proxy and error processing."""
    requests, bodies, constructors = [], [], []
    original = urllib.request.build_opener

    class FixtureTransport(urllib.request.HTTPHandler, urllib.request.HTTPSHandler):
        def http_open(self, request):
            requests.append(request)
            status, headers, data = responder(request)
            message = Message()
            for key, value in headers.items():
                message[key] = value
            stream = Body(data, request.host == posture.API_HOST and status == 200)
            bodies.append(stream)
            response = urllib.response.addinfourl(stream, message, request.full_url, status)
            response.msg = "fixture"
            return response

        https_open = http_open

    def build(*handlers):
        constructors.append(handlers)
        assert any(isinstance(handler, urllib.request.ProxyHandler) and handler.proxies == {} for handler in handlers)
        assert any(isinstance(handler, posture.NoRedirect) for handler in handlers)
        return original(*handlers, FixtureTransport())

    monkeypatch.setattr(urllib.request, "getproxies", forbidden)
    monkeypatch.setattr(urllib.request, "build_opener", build)
    return SimpleNamespace(requests=requests, bodies=bodies, constructors=constructors)


def success(name, value):
    return {"success": True, "result": {"id": name, "value": value, "extra": SECRET}, "extra": SECRET}


def encoded(value):
    return json.dumps(value).encode()


def disable_tls_client(monkeypatch):
    def unsupported():
        raise ValueError(SECRET)
    monkeypatch.setattr(posture.ssl, "create_default_context", unsupported)


def test_regression_snapshot_arbitrary_value():
    assert posture._normalize_snapshot({"settings": {"ssl": SECRET}})["ssl"] is None


def test_regression_api_wrong_identity():
    assert posture._setting_value(success("ssl", "on"), "always_use_https") is None


def test_regression_location_secret_path():
    assert SECRET not in str(posture.sanitize_location(f"https://keycloak.3ai-talk.org/{SECRET}", "https", "grafana.3ai-talk.org"))


def test_regression_local_low_version_is_not_edge_rejection():
    assert posture._tls_error_kind(ssl.SSLError("VERSION_TOO_LOW: version too low")) != "edge_rejected"


def test_regression_context_value_error(monkeypatch):
    disable_tls_client(monkeypatch)
    assert posture.probe_tls("grafana.3ai-talk.org", "1.2")["result"] == "client_unsupported"


@pytest.mark.parametrize("argv", [[], ["--dry-run"], ["--help"], ["-h"],
                                  ["--dry-run", "--settings-file", "/must-not-open"]])
def test_zero_access_includes_environment_files_processes_and_network(argv, monkeypatch, capsys):
    with monkeypatch.context() as patch:
        patch.setattr(posture.os, "environ", NoEnvironment())
        patch.setattr(posture.os, "getenv", forbidden)
        patch.setattr(posture.os, "system", forbidden)
        patch.setattr(subprocess, "run", forbidden)
        patch.setattr(builtins, "open", forbidden)
        patch.setattr(urllib.request, "build_opener", forbidden)
        patch.setattr(posture, "read_api", forbidden)
        patch.setattr(posture, "read_snapshot", forbidden)
        assert posture.main(argv) == 0
    assert capsys.readouterr().out


@pytest.mark.parametrize("name,value", [
    (name, value) for name, values in posture.SETTING_VALUES.items() for value in values
] + [("security_header", {"strict_transport_security": {"enabled": enabled, "extra": SECRET}, "extra": SECRET})
     for enabled in (True, False)])
def test_documented_values_and_strict_identity(name, value):
    expected = value if name != "security_header" else {"strict_transport_security": {"enabled": value["strict_transport_security"]["enabled"]}}
    assert posture._setting_value(success(name, value), name) == expected
    assert posture._setting_value(success("wrong-id", value), name) is None
    assert posture._setting_value({"success": True, "result": {"value": value}}, name) is None
    assert posture._setting_value({"success": False, "result": {"id": name, "value": value}}, name) is None


@pytest.mark.parametrize("value", [SECRET, True, False, 1, 1.2, [SECRET], {"extra": SECRET}, None])
@pytest.mark.parametrize("name", posture.SETTING_NAMES)
def test_invalid_types_and_values_never_echo(name, value):
    assert posture._setting_value(success(name, value), name) is None
    assert posture._normalize_snapshot({"settings": {name: value}})[name] is None


@pytest.mark.parametrize("shape", ["map", "wrapped_map", "response_map", "result_map", "list_envelope", "single_envelope"])
def test_safe_snapshot_shapes(shape, tmp_path):
    values = {"always_use_https": "on", "min_tls_version": "1.2", "ssl": "strict",
              "security_header": {"strict_transport_security": {"enabled": False}}, "tls_1_3": "on"}
    shapes = {
        "map": values, "wrapped_map": {"settings": values},
        "response_map": {name: success(name, value) for name, value in values.items()},
        "result_map": {name: {"id": name, "value": value} for name, value in values.items()},
        "list_envelope": {"success": True, "result": [success(name, value)["result"] for name, value in values.items()]},
        "single_envelope": success("always_use_https", "on"),
    }
    path = tmp_path / "snapshot.json"
    path.write_text(json.dumps(shapes[shape]))
    result, error = posture.read_snapshot(path)
    assert error is None
    assert result == (dict.fromkeys(posture.SETTING_NAMES) | {"always_use_https": "on"} if shape == "single_envelope" else values)


def test_duplicate_snapshot_result_ids_are_unknown():
    payload = {"success": True, "result": [success("ssl", "full")["result"], success("ssl", "strict")["result"]]}
    assert posture._normalize_snapshot(payload)["ssl"] is None


@pytest.mark.parametrize("body", [b"{", b"\xff", b" " * (posture.MAX_BYTES + 1), b"[]", b"null"])
def test_bad_or_oversized_snapshots_are_unknown(tmp_path, body):
    path = tmp_path / "snapshot.json"
    path.write_bytes(body)
    settings, _ = posture.read_snapshot(path)
    assert all(value is None for value in settings.values())
    assert posture.posture(settings) == {"https_enforcement": "unknown", "minimum_tls": "unknown"}


def test_snapshot_read_has_explicit_byte_bound(monkeypatch):
    body = Body(encoded({"ssl": "full"}), True)
    with mock.patch.object(builtins, "open", return_value=body):
        assert posture.read_snapshot("fixture")[0]["ssl"] == "full"
    assert body.read_sizes == [posture.MAX_BYTES + 1]


@pytest.mark.parametrize("case", ["invalid_value", "wrong_id", "missing_id", "http403", "successfalse", "malformed", "oversized", "valid"])
def test_fake_api_report_sanitizes_end_to_end(case, monkeypatch, capsys):
    monkeypatch.setenv("CLOUDFLARE_API_TOKEN", SECRET)
    disable_tls_client(monkeypatch)

    def respond(request):
        if request.host != posture.API_HOST:
            return 302, {"Location": f"https://keycloak.3ai-talk.org/{SECRET}?token={SECRET}"}, b"never read public body"
        name = request.full_url.rsplit("/", 1)[-1]
        values = {"always_use_https": "on", "min_tls_version": "1.2", "ssl": "full",
                  "security_header": {"strict_transport_security": {"enabled": True, "extra": SECRET}}, "tls_1_3": "on"}
        payload = success(name, values[name])
        if case == "invalid_value":
            payload = success(name, SECRET)
        if case == "wrong_id":
            payload["result"]["id"] = SECRET
        if case == "missing_id":
            del payload["result"]["id"]
        if case == "successfalse":
            payload["success"] = False
        body = {"malformed": b"{" + SECRET.encode(), "oversized": SECRET.encode() + b" " * posture.MAX_BYTES,
                "http403": SECRET.encode()}.get(case, encoded(payload))
        return (403 if case == "http403" else 200), {}, body

    observed = install_transport(monkeypatch, respond)
    assert posture.main(["--check", "--zone-id", ZONE, "--timeout", "3"]) == 0
    raw = capsys.readouterr().out
    report = json.loads(raw)
    assert SECRET not in raw
    assert report["f0_complete"] is False
    if case == "valid":
        assert report["posture"] == {"https_enforcement": "on", "minimum_tls": "1.2"}
    else:
        assert report["settings"] == dict.fromkeys(posture.SETTING_NAMES)
        assert report["posture"] == {"https_enforcement": "unknown", "minimum_tls": "unknown"}
        assert report["source_error"]
    assert len(observed.requests) == 5 + 14
    for request in observed.requests:
        assert request.get_method() == "GET" and request.data is None
        assert request.timeout == 3
        if request.host == posture.API_HOST:
            assert request.full_url.startswith(f"https://api.cloudflare.com/client/v4/zones/{ZONE}/settings/")
            assert request.full_url.rsplit("/", 1)[-1] in posture.SETTING_NAMES
            assert request.get_header("Authorization") == f"Bearer {SECRET}"
        else:
            assert request.host in posture.HOSTS and request.selector == "/"
            assert request.get_header("Authorization") is None


def test_snapshot_report_does_not_read_credentials_and_is_not_api_confirmation(tmp_path, monkeypatch, capsys):
    path = tmp_path / "snapshot.json"
    path.write_text(json.dumps({"settings": {"ssl": SECRET, "always_use_https": "off", "min_tls_version": "1.0", "extra": SECRET}}))
    disable_tls_client(monkeypatch)
    observed = install_transport(monkeypatch, lambda request: (401, {}, b"secret body never read"))
    original_get = os.environ.get
    def credential_guard(key, *args):
        assert key != "CLOUDFLARE_API_TOKEN", "snapshot must not look up API credentials"
        return original_get(key, *args)
    with mock.patch.object(os.environ, "get", credential_guard):
        assert posture.main(["--check", "--settings-file", str(path)]) == 0
    raw = capsys.readouterr().out
    result = json.loads(raw)
    assert SECRET not in raw and result["settings"]["ssl"] is None
    assert "snapshot" in result["source"] and "not a current API read" in result["source"]
    assert result["posture"] == {"https_enforcement": "off", "minimum_tls": "1.0"}
    assert result["f0_complete"] is False and "report completion only" in result["exit_status_meaning"]
    assert all(request.host in posture.HOSTS for request in observed.requests)


@pytest.mark.parametrize("code", [301, 302, 307, 308])
def test_authenticated_api_redirect_is_never_followed(code, monkeypatch):
    monkeypatch.setenv("HTTPS_PROXY", f"https://{SECRET}.invalid")
    observed = install_transport(monkeypatch, lambda request: (code, {"Location": f"https://{SECRET}.invalid/steal"}, b"error-body"))
    assert posture.read_api_setting(ZONE, SECRET, "ssl", 2) is None
    assert len(observed.requests) == 1
    assert observed.bodies[0].read_sizes == []


@pytest.mark.parametrize("scheme,code,location,transport,equivalent,self_redirect", [
    ("http", 301, "https://grafana.3ai-talk.org/", "upgrade", True, False),
    ("http", 308, "https://grafana.3ai-talk.org/", "upgrade", True, False),
    ("https", 302, f"https://keycloak.3ai-talk.org/{SECRET}?code={SECRET}", "same_scheme", False, False),
    ("https", 302, "http://grafana.3ai-talk.org/", "downgrade", False, False),
    ("https", 302, "/", "same_scheme", False, True),
    ("http", 301, f"https://grafana.3ai-talk.org/{SECRET}", "upgrade", False, False),
])
def test_redirect_upgrade_auth_downgrade_and_self_loop_observations(scheme, code, location, transport, equivalent, self_redirect, monkeypatch):
    observed = install_transport(monkeypatch, lambda request: (code, {"Location": location}, b"not read"))
    result = posture.probe_http(scheme, "grafana.3ai-talk.org", 2)
    assert result["status"] == code
    assert result["redirect"]["transport"] == transport
    assert result["redirect"]["https_equivalent"] is equivalent
    assert result["redirect"]["self_redirect"] is self_redirect
    assert SECRET not in json.dumps(result)
    assert len(observed.requests) == 1
    assert observed.requests[0].get_header("Authorization") is None
    assert observed.requests[0].timeout == 2
    assert observed.bodies[0].read_sizes == []


@pytest.mark.parametrize("location", [f"https://user:{SECRET}@keycloak.3ai-talk.org/{SECRET}?secret={SECRET}#{SECRET}",
                                      f"https://{SECRET}.invalid/{SECRET}", f"/{SECRET}",
                                      f"javascript:{SECRET}", "https://[invalid", "https://grafana.3ai-talk.org:bad/"])
def test_location_never_echoes_noncontrolled_header_text(location):
    assert SECRET not in json.dumps(posture._http_observation(302, location, "https", "grafana.3ai-talk.org"))


@pytest.mark.parametrize("status", [200, 401, 403, 502])
def test_https_status_is_only_an_unauthenticated_baseline(status, monkeypatch):
    observed = install_transport(monkeypatch, lambda request: (status, {}, b"not read"))
    result = posture.probe_http("https", "webhook.3ai-talk.org", 2)
    assert result == {"status": status, "location": None, "redirect": None, "result": "response"}
    assert observed.bodies[0].read_sizes == []


def ssl_error(reason, text=SECRET):
    error = ssl.SSLError(ssl.SSL_ERROR_SSL, text)
    error.reason = reason
    return error


@pytest.mark.parametrize("error,expected", [
    (ssl_error("TLSV1_ALERT_PROTOCOL_VERSION"), "edge_rejected"),
    (ssl_error("VERSION_TOO_LOW"), "client_unsupported"),
    (ssl_error("NO_PROTOCOLS_AVAILABLE"), "client_unsupported"),
    (ssl_error("NO_CIPHERS_AVAILABLE"), "client_unsupported"),
    (ssl_error("UNSUPPORTED_PROTOCOL"), "client_unsupported"),
    (ssl_error("SSLV3_ALERT_HANDSHAKE_FAILURE"), "inconclusive"),
    (ssl.SSLError("tlsv1 alert protocol version"), "inconclusive"),
    (ssl.SSLError("VERSION_TOO_LOW: version too low"), "inconclusive"),
    (ssl.SSLCertVerificationError(SECRET), "certificate_error"),
    (socket.gaierror(SECRET), "dns_or_timeout"),
    (TimeoutError(SECRET), "dns_or_timeout"),
    (OSError(SECRET), "inconclusive"),
])
def test_tls_failure_classification_through_real_probe(error, expected, monkeypatch):
    class Context:
        def wrap_socket(self, raw, server_hostname):
            raise error
    monkeypatch.setattr(ssl, "create_default_context", Context)
    class Raw:
        def __enter__(self): return self
        def __exit__(self, *args): pass
    monkeypatch.setattr(socket, "create_connection", lambda address, timeout: Raw())
    result = posture.probe_tls("grafana.3ai-talk.org", "1.2", 2)
    assert result["result"] == expected
    assert result["negotiated"] is None
    assert result["certificate_valid"] is (False if expected == "certificate_error" else None)
    assert SECRET not in json.dumps(result)


@pytest.mark.parametrize("phase", ["factory", "minimum", "maximum"])
@pytest.mark.parametrize("exception", [ValueError, NotImplementedError])
def test_unsupported_context_configuration_never_opens_socket(phase, exception, monkeypatch):
    class Context:
        def __setattr__(self, name, value):
            if name == f"{phase}_version":
                raise exception(SECRET)
    def factory():
        if phase == "factory":
            raise exception(SECRET)
        return Context()
    monkeypatch.setattr(ssl, "create_default_context", factory)
    assert posture.probe_tls("grafana.3ai-talk.org", "1.2", 2) == {
        "result": "client_unsupported", "negotiated": None, "certificate_valid": None}


@pytest.mark.filterwarnings("ignore:ssl.TLSVersion.TLSv1.*:DeprecationWarning")
@pytest.mark.parametrize("host", posture.HOSTS)
@pytest.mark.parametrize("version", VERSIONS)
def test_actual_context_protocol_bounds_sni_validation_and_timeout(host, version, monkeypatch):
    # A real local SSLContext validates both version setters; no real socket exists.
    context = ssl.create_default_context()
    observed = {}
    selected, negotiated = VERSIONS[version]
    def wrap(raw, server_hostname):
        observed["sni"] = server_hostname
        assert context.minimum_version == selected and context.maximum_version == selected
        assert context.check_hostname is True and context.verify_mode == ssl.CERT_REQUIRED
        return SimpleNamespace(__unused=True)
    class Secured:
        def __enter__(self): return self
        def __exit__(self, *args): pass
        def version(self): return negotiated
    def wrap_socket(raw, server_hostname):
        wrap(raw, server_hostname)
        return Secured()
    class Raw:
        def __enter__(self): return self
        def __exit__(self, *args): pass
    def connect(address, timeout):
        observed.update(address=address, timeout=timeout)
        return Raw()
    monkeypatch.setattr(context, "wrap_socket", wrap_socket)
    monkeypatch.setattr(ssl, "create_default_context", lambda: context)
    monkeypatch.setattr(socket, "create_connection", connect)
    assert posture.probe_tls(host, version, 3) == {"result": "negotiated", "negotiated": negotiated, "certificate_valid": True}
    assert observed == {"sni": host, "address": (host, 443), "timeout": 3}


@pytest.mark.parametrize("value,observed", [("TLSv1.3", "TLSv1.3"), (SECRET, None), (None, None)])
def test_unexpected_negotiated_protocol_is_not_a_pass(value, observed, monkeypatch):
    class Secured:
        def __enter__(self): return self
        def __exit__(self, *args): pass
        def version(self): return value
    class Context:
        def wrap_socket(self, raw, server_hostname): return Secured()
    monkeypatch.setattr(ssl, "create_default_context", Context)
    monkeypatch.setattr(socket, "create_connection", lambda address, timeout: Secured())
    result = posture.probe_tls("grafana.3ai-talk.org", "1.2", 2)
    assert result["result"] == "inconclusive" and result["negotiated"] == observed


@pytest.mark.parametrize("timeout", ["0", "21", "nan", "inf", "bad"])
def test_timeout_bounds_reject_without_access(timeout, capsys):
    assert posture.main(["--check", "--timeout", timeout]) == 2
    assert "Invalid arguments" in capsys.readouterr().err


def test_missing_credentials_unknown_report(monkeypatch, capsys):
    monkeypatch.delenv("CLOUDFLARE_API_TOKEN", raising=False)
    disable_tls_client(monkeypatch)
    observed = install_transport(monkeypatch, lambda request: (401, {}, b"not read"))
    assert posture.main(["--check", "--zone-id", ZONE]) == 0
    report = json.loads(capsys.readouterr().out)
    assert report["posture"] == {"https_enforcement": "unknown", "minimum_tls": "unknown"}
    assert report["settings"] == dict.fromkeys(posture.SETTING_NAMES)
    assert report["f0_complete"] is False and len(observed.requests) == 14


def test_api_invalid_zone_or_setting_does_not_construct_opener(monkeypatch):
    monkeypatch.setattr(posture, "_api_opener", forbidden)
    assert posture.read_api_setting("../", SECRET, "ssl") is None
    assert posture.read_api_setting(ZONE, SECRET, "../ssl") is None


def test_direct_executable_help_and_dry_run():
    for args in (["--help"], [], ["--dry-run"]):
        result = subprocess.run([str(SCRIPT), *args], capture_output=True, text=True, check=False)
        assert result.returncode == 0 and result.stdout and not result.stderr


@pytest.mark.parametrize("version", VERSIONS)
def test_protocol_missing_from_client_is_unsupported(version, monkeypatch):
    monkeypatch.setattr(ssl, "TLSVersion", SimpleNamespace())
    assert posture.probe_tls("grafana.3ai-talk.org", version, 2) == {
        "result": "client_unsupported", "negotiated": None, "certificate_valid": None}
