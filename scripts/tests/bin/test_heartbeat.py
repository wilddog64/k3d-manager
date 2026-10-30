"""Offline tests for independent heartbeat probing and rendering."""
import importlib.machinery
import importlib.util
import json
import plistlib
import sys
import threading
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]


def _load(name, path):
    spec = importlib.util.spec_from_loader(name, importlib.machinery.SourceFileLoader(name, str(path)))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


heartbeat = _load("heartbeat_test", ROOT / "bin/k3dm-heartbeat")
setup = _load("heartbeat_setup_test", ROOT / "bin/k3dm-heartbeat-setup")
M4_IDS = ["m4-host", "m4-hermes", "m4-webhook", "m4-cloud-bridge"]
PING_URL = "https://hc-ping.com/11111111-1111-1111-1111-111111111111"


def _write_config(directory, raw):
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "config.json"
    path.write_text(json.dumps(raw))
    return path


def _config(directory, role="m4", enabled=True, disabled=None):
    identities = M4_IDS if role == "m4" else ["hostinger"]
    disabled = set(disabled or [])
    checks = []
    for identity in identities:
        source = ({"type": "file", "path": str(directory / "hostinger.url")} if identity == "hostinger"
                  else {"type": "keychain", "service": f"k3dm-heartbeat-{identity}"})
        checks.append({"id": identity, "period_seconds": 120 if identity in ("hostinger", "m4-cloud-bridge") else 60,
                       "grace_seconds": 1800 if identity == "m4-hermes" else
                       360 if identity in ("hostinger", "m4-cloud-bridge") else 180,
                       "disabled": identity in disabled, "secret_source": source})
    raw = {"role": role, "enabled": enabled, "state_dir": str(directory / "state"), "checks": checks,
           "hermes_marker": str(directory / "hermes.timestamp"), "hermes_freshness_seconds": 1200,
           "bridge_marker": str(directory / "bridge.timestamp"), "bridge_freshness_seconds": 180,
           "webhook_url": "http://127.0.0.1:9000/api/v1/health?quick=1",
           "webhook_reader_token_service": "k3dm-webhook-token-reader"}
    return _write_config(directory, raw)


def test_marker_freshness_rejects_stale_future_and_malformed_values(tmp_path):
    marker = tmp_path / "marker"
    marker.write_text("1000")
    assert heartbeat._marker_fresh(marker, 1200, 1100)
    assert not heartbeat._marker_fresh(marker, 1200, 2201)
    marker.write_text("1201")
    assert not heartbeat._marker_fresh(marker, 1200, 1200)
    marker.write_text("not-a-timestamp")
    assert not heartbeat._marker_fresh(marker, 1200, 1200)


@pytest.mark.parametrize("role,identities", [("m4", M4_IDS), ("hostinger", ["hostinger"])])
def test_dry_run_never_probes_reads_state_or_touches_secret_or_network(
        tmp_path, monkeypatch, role, identities):
    config = _config(tmp_path, role=role)

    def forbidden(*_args, **_kwargs):
        pytest.fail("dry-run performed an external dependency operation")

    for name in ("probe", "_secret", "_marker_fresh", "_webhook", "_interval_attempt"):
        monkeypatch.setattr(heartbeat, name, forbidden)
    monkeypatch.setattr(heartbeat.subprocess, "run", forbidden)
    monkeypatch.setattr(heartbeat.urllib.request, "build_opener", forbidden)
    outcomes, success = heartbeat.run(config, dry_run=True)
    assert success
    assert [name for name, _ in outcomes] == identities
    assert all(value == "dry-run: would probe and report" for _, value in outcomes)
    assert not (tmp_path / "state").exists()


def test_disabled_by_default_config_dry_run_plans_no_work(tmp_path, monkeypatch):
    config = _config(tmp_path, enabled=False)
    monkeypatch.setattr(heartbeat, "probe", lambda *_a, **_k: pytest.fail("disabled config probed"))
    outcomes, success = heartbeat.run(config, dry_run=True)
    assert success
    assert all(value == "suppressed: disabled" for _, value in outcomes)


def test_repository_example_is_complete_m4_profile_and_disabled():
    config = json.loads((ROOT / "scripts/etc/heartbeat/checks.example.json").read_text())
    heartbeat._validate_config(config, expected_role="m4")
    assert config["enabled"] is False
    assert all(entry["disabled"] for entry in config["checks"])


def test_role_identity_and_duplicate_validation_precedes_any_effect(tmp_path, monkeypatch):
    wrong = _config(tmp_path)
    raw = json.loads(wrong.read_text())
    raw["checks"].append({"id": "hostinger"})
    wrong.write_text(json.dumps(raw))
    monkeypatch.setattr(heartbeat, "probe", lambda *_a, **_k: pytest.fail("probed invalid config"))
    with pytest.raises(ValueError, match="identities"):
        heartbeat.run(wrong)
    raw["checks"] = [raw["checks"][0]] * len(M4_IDS)
    wrong.write_text(json.dumps(raw))
    with pytest.raises(ValueError, match="unique"):
        heartbeat.run(wrong)
    m4_config = _config(tmp_path / "valid-m4")
    with pytest.raises(ValueError, match="does not belong"):
        heartbeat.run(m4_config, identity="hostinger")


@pytest.mark.parametrize("url", [
    "http://127.0.0.1:9000@attacker.example/api/v1/health?quick=1",
    "http://localhost:9000@attacker.example/api/v1/health?quick=1",
    "http://127.0.0.2:9000/api/v1/health?quick=1",
    "http://127.0.0.1:99999/api/v1/health?quick=1",
    "http://127.0.0.1:bad/api/v1/health?quick=1",
    "http://127.0.0.1:9000/other?quick=1",
    "http://127.0.0.1:9000/api/v1/health?quick=1&token=x",
    "http://user@127.0.0.1:9000/api/v1/health?quick=1",
])
def test_bad_webhook_url_fails_validation_before_reader_token_lookup(tmp_path, monkeypatch, url):
    config = _config(tmp_path)
    raw = json.loads(config.read_text())
    raw["webhook_url"] = url
    config.write_text(json.dumps(raw))
    monkeypatch.setattr(heartbeat.subprocess, "run", lambda *_a, **_k:
                        pytest.fail("invalid URL reached credential lookup"))
    with pytest.raises(ValueError, match="webhook URL"):
        heartbeat.run(config)


def test_webhook_uses_reader_credential_validates_schema_and_distinguishes_downstream(monkeypatch):
    class Response:
        status = 200

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def geturl(self):
            return "http://127.0.0.1:9000/api/v1/health?quick=1"

        def read(self, _limit):
            return b'{"all_ok":false,"services":[{"name":"example","ok":false,"detail":"down"}]}'

    commands = []
    monkeypatch.setattr(heartbeat.subprocess, "run", lambda argv, **_kw:
                        commands.append(argv) or type("Result", (), {"returncode": 0, "stdout": "reader"})())
    requests = []

    def open_request(request, timeout):
        requests.append((request.full_url, request.get_header("Authorization"), timeout))
        return Response()

    monkeypatch.setattr(heartbeat.urllib.request, "build_opener",
                        lambda *_handlers: type("Client", (), {"open": staticmethod(open_request)})())
    valid, downstream_ok = heartbeat._webhook(
        {"webhook_url": "http://127.0.0.1:9000/api/v1/health?quick=1"}, 4)
    assert (valid, downstream_ok) == (True, False)
    assert "k3dm-webhook-token-reader" in commands[0]
    assert requests == [("http://127.0.0.1:9000/api/v1/health?quick=1", "Bearer reader", 4)]


def test_webhook_redirect_is_rejected_without_following(monkeypatch):
    calls = []
    monkeypatch.setattr(heartbeat.subprocess, "run", lambda *_a, **_kw:
                        type("Result", (), {"returncode": 0, "stdout": "reader"})())

    class Client:
        def open(self, request, timeout):
            calls.append((request.full_url, timeout))
            raise heartbeat.urllib.error.HTTPError(request.full_url, 302, "redirect", {}, None)

    monkeypatch.setattr(heartbeat.urllib.request, "build_opener", lambda *_a: Client())
    assert heartbeat._webhook(
        {"webhook_url": "http://127.0.0.1:9000/api/v1/health?quick=1"}, 4) == (False, None)
    assert calls == [("http://127.0.0.1:9000/api/v1/health?quick=1", 4)]


def test_provider_redirect_is_not_followed_or_reported_successfully():
    class Redirect:
        status = 302

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def geturl(self):
            return "https://attacker.example/collect"

    assert not heartbeat.send(PING_URL, False, opener=lambda *_a, **_kw: Redirect())


def test_healthcheck_secret_is_uuid_https_without_userinfo_or_nonstandard_port(tmp_path):
    secret = tmp_path / "url"
    secret.write_text(PING_URL)
    secret.chmod(0o600)
    entry = {"secret_source": {"type": "file", "path": str(secret)}}
    assert heartbeat._secret(entry) == PING_URL
    for bad in ("http://hc-ping.com/11111111-1111-1111-1111-111111111111",
                "https://user@hc-ping.com/11111111-1111-1111-1111-111111111111",
                "https://hc-ping.com:444/11111111-1111-1111-1111-111111111111",
                "https://hc-ping.com:/11111111-1111-1111-1111-111111111111",
                "https://hc-ping.com/11111111-1111-1111-1111-111111111111/",
                "https://hc-ping.com/not-a-uuid"):
        secret.write_text(bad)
        with pytest.raises(ValueError, match="endpoint"):
            heartbeat._secret(entry)
    secret.write_text("https://hc-ping.com/11111111-1111-1111-1111-111111111111")
    secret.chmod(0o640)
    with pytest.raises(ValueError, match="permissions"):
        heartbeat._secret(entry)


def test_operator_credential_validation_is_local_and_redacted(tmp_path, monkeypatch):
    config = _config(tmp_path, enabled=False)
    calls = []

    def fake_secret(entry):
        calls.append(entry["id"])
        if entry["id"] == "m4-host":
            raise ValueError("credential value must never appear")
        return PING_URL

    monkeypatch.setattr(heartbeat, "_secret", fake_secret)
    monkeypatch.setattr(heartbeat.subprocess, "run", lambda *_a, **_kw:
                        type("Result", (), {"returncode": 0, "stdout": "reader-token"})())
    results, success = heartbeat.validate_credentials(config)
    assert not success and len(calls) == len(M4_IDS)
    assert results[-1] == ("m4-webhook-reader", "credential valid")
    assert results[0] == ("m4-host", "credential invalid: invalid local configuration or response")
    assert "credential value" not in str(results)


def test_independent_failures_do_not_abort_and_aggregate_is_false(tmp_path, monkeypatch):
    config = _config(tmp_path)
    sent = []
    monkeypatch.setattr(heartbeat, "probe", lambda *_a, **_kw: (True, "ok"))

    def secret(entry):
        if entry["id"] == "m4-host":
            raise RuntimeError("do not display a sensitive exception detail")
        return PING_URL

    monkeypatch.setattr(heartbeat, "_secret", secret)
    monkeypatch.setattr(heartbeat, "send", lambda url, failed, _timeout:
                        sent.append((url, failed)) or True)
    outcomes, success = heartbeat.run(config, now=1000)
    assert not success
    assert [identity for identity, _ in outcomes] == M4_IDS
    assert outcomes[0][1] == "failed: check failed"
    assert "sensitive" not in str(outcomes)
    assert len(sent) == 3


def test_probe_exception_reports_failure_and_continues_other_checks(tmp_path, monkeypatch):
    config = _config(tmp_path)
    reports = []
    monkeypatch.setattr(heartbeat, "_secret", lambda _entry: PING_URL)

    def probe(identity, *_args):
        if identity == "m4-host":
            raise RuntimeError("private probe exception text")
        return True, "ok"

    monkeypatch.setattr(heartbeat, "probe", probe)
    monkeypatch.setattr(heartbeat, "send", lambda _url, failed, _timeout:
                        reports.append(failed) or True)
    outcomes, success = heartbeat.run(config, now=4000)
    assert not success and len(outcomes) == len(M4_IDS)
    assert outcomes[0] == ("m4-host", "failed: check failed; failure report sent")
    assert "private probe exception text" not in str(outcomes)
    assert reports == [True, False, False, False]


def test_probe_failure_report_recovery_and_provider_failure_are_truthful(tmp_path, monkeypatch):
    config = _config(tmp_path)
    monkeypatch.setattr(heartbeat, "_secret", lambda _entry: PING_URL)
    monkeypatch.setattr(heartbeat, "probe", lambda *_a, **_kw: (False, "local check failed"))
    reports = []
    monkeypatch.setattr(heartbeat, "send", lambda _url, failed, _timeout:
                        reports.append(failed) or False)
    outcomes, success = heartbeat.run(config, "m4-host", now=1000)
    assert not success and outcomes[0][1] == "failed: provider report unavailable"
    monkeypatch.setattr(heartbeat, "send", lambda _url, failed, _timeout:
                        reports.append(failed) or True)
    monkeypatch.setattr(heartbeat, "probe", lambda *_a, **_kw: (True, "restored"))
    outcomes, success = heartbeat.run(config, "m4-host", now=1060)
    assert success and outcomes[0][1] == "healthy: restored; report sent"
    assert reports == [True, False]


def test_interval_lock_is_held_through_slow_report_and_recovers_after_process(tmp_path, monkeypatch):
    config = _config(tmp_path)
    entered = threading.Event()
    release = threading.Event()
    calls = []
    monkeypatch.setattr(heartbeat, "probe", lambda *_a, **_kw: (True, "ok"))
    monkeypatch.setattr(heartbeat, "_secret", lambda _entry: PING_URL)

    def slow_send(*_args):
        calls.append(1)
        entered.set()
        release.wait(2)
        return True

    monkeypatch.setattr(heartbeat, "send", slow_send)
    first = threading.Thread(target=heartbeat.run, args=(config, "m4-host"), kwargs={"now": 2000})
    first.start()
    assert entered.wait(1)
    outcomes, success = heartbeat.run(config, "m4-host", now=2000)
    assert success and "already running" in outcomes[0][1]
    release.set()
    first.join(2)
    assert not first.is_alive() and calls == [1]
    # The OS releases flock when the holder exits; the persistent lock file is safe to reuse.
    outcomes, _success = heartbeat.run(config, "m4-host", now=2060)
    assert "healthy" in outcomes[0][1] and calls == [1, 1]


def test_120_second_cadence_maintenance_future_and_invalid_clock(tmp_path, monkeypatch):
    config = _config(tmp_path, role="hostinger")
    monkeypatch.setattr(heartbeat, "_secret", lambda _entry: PING_URL)
    monkeypatch.setattr(heartbeat, "probe", lambda *_a, **_kw: (True, "ok"))
    sent = []
    monkeypatch.setattr(heartbeat, "send", lambda *_a, **_kw: sent.append(1) or True)
    assert "healthy" in heartbeat.run(config, now=1200)[0][0][1]
    assert "not due" in heartbeat.run(config, now=1260)[0][0][1]
    assert "healthy" in heartbeat.run(config, now=1320)[0][0][1]
    raw = json.loads(config.read_text())
    raw["checks"][0]["maintenance_until"] = 1500
    config.write_text(json.dumps(raw))
    assert heartbeat.run(config, now=1400)[0][0][1] == "suppressed: maintenance"
    for value in (-1, float("nan"), float("inf"), "bad"):
        with pytest.raises(ValueError, match="clock"):
            heartbeat.run(config, now=value)
    assert sent == [1, 1]


def test_future_freshness_marker_never_reports_healthy(tmp_path):
    marker = tmp_path / "future.timestamp"
    marker.write_text("1001")
    assert not heartbeat._marker_fresh(marker, 1200, 1000)


@pytest.mark.parametrize("platform,role", [("launchd", "m4"), ("systemd", "hostinger")])
def test_setup_renders_role_specific_candidates_and_never_overwrites(
        tmp_path, platform, role):
    config = _config(tmp_path, role=role, enabled=False)
    out = tmp_path / "output with spaces"
    python_path = tmp_path / "python path with spaces"
    python_path.symlink_to(Path(sys.executable))
    paths = setup.render(config, out, platform, python_path=str(python_path))
    assert len(paths) == (2 if platform == "launchd" else 3)
    generated = [Path(path) for path in paths]
    if platform == "launchd":
        plist = plistlib.loads(generated[1].read_bytes())
        assert plist["ProgramArguments"][0] == str(python_path)
        assert plist["StartInterval"] == 60
    else:
        service = generated[1].read_text()
        assert f'"{python_path}"' in service and '"' in service
        assert "OnUnitActiveSec=60s" in generated[2].read_text()
    with pytest.raises(FileExistsError):
        setup.render(config, out, platform, python_path=str(python_path))


def test_setup_rejects_cross_role_render_and_templates_validate(tmp_path):
    config = _config(tmp_path, role="m4", enabled=False)
    with pytest.raises(ValueError, match="role/platform"):
        setup.render(config, tmp_path / "wrong", "systemd", python_path=sys.executable)
    plist = plistlib.loads((ROOT / "scripts/etc/launchd/com.k3d-manager.heartbeat.plist.tmpl").read_bytes())
    assert plist["Label"] == "com.k3d-manager.heartbeat" and plist["StartInterval"] == 60
    service = (ROOT / "scripts/etc/systemd/k3dm-heartbeat.service.tmpl").read_text()
    timer = (ROOT / "scripts/etc/systemd/k3dm-heartbeat.timer.tmpl").read_text()
    assert "Type=oneshot" in service and "{{PYTHON3}}" in service
    assert "OnUnitActiveSec=60s" in timer and "Persistent=true" in timer


def test_webhook_default_and_enrollment_example_use_server_port(monkeypatch):
    seen = []
    monkeypatch.setattr(heartbeat, "_reader_token", lambda: "reader")
    class Response:
        status = 200
        def __enter__(self): return self
        def __exit__(self, *_args): return False
        def geturl(self): return "http://127.0.0.1:7443/api/v1/health?quick=1"
        def read(self, _limit):
            return b'{"services":[{"name":"api","ok":true,"detail":"ok"}],"all_ok":true}'
    class Client:
        def open(self, request, timeout):
            seen.append(request.full_url)
            return Response()
    monkeypatch.setattr(heartbeat.urllib.request, "build_opener", lambda *_args: Client())
    assert heartbeat._webhook({}, 4) == (True, True)
    assert seen == ["http://127.0.0.1:7443/api/v1/health?quick=1"]
    example = json.loads((ROOT / "scripts/etc/heartbeat/checks.example.json").read_text())
    assert example["webhook_url"] == seen[0]
