"""Offline tests for notification route configuration."""
import importlib
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts/lib"))
from webhook import notify_routes as routes
from webhook.cloud_actions import ACTION_ALLOWLIST


def test_valid_boundary():
    raw = ",".join(f"a{i}:C{i:08d}" for i in range(8))
    raw += " " * (512 - len(raw))
    assert len(raw.encode()) == 512
    assert len(routes.parse_routes(raw)) == 8
    assert routes.parse_routes(" \t") == {}
    assert routes.parse_routes(" test : C12345678 ") == {"test": "C12345678"}


@pytest.mark.parametrize("raw", [
    "default:C12345678", ",".join(f"a{i}:C{i:08d}" for i in range(9)),
    "a:C12345678" + " " * 502, "a:C12345678,a:C87654321",
    "a:C12345678,b:C12345678", "Bad:C12345678", "a:c12345678",
    "aC12345678", "a:C12345678:extra", "a:C12345678,",
])
def test_rejection_and_redaction(raw):
    with pytest.raises(routes.RouteMapError) as exc:
        routes.parse_routes(raw)
    assert str(exc.value) == "invalid notification route map"
    assert raw not in str(exc.value)


def test_load_and_names(monkeypatch):
    monkeypatch.setenv("SLACK_SIGNING_SECRET", "fixture")
    from webhook import auth
    calls = []
    monkeypatch.setattr(auth, "_keychain_secret", lambda service: calls.append(service) or "key:C12345678")
    monkeypatch.setenv(routes.ENV_VAR, "env:C87654321")
    assert routes.load_routes() == ({"env": "C87654321"}, "ok")
    assert routes.route_names() == frozenset({"env"})
    assert calls == []
    monkeypatch.setenv(routes.ENV_VAR, "")
    assert routes.load_routes() == ({"key": "C12345678"}, "ok")
    assert calls == [routes.KEYCHAIN_SERVICE]
    monkeypatch.setattr(auth, "_keychain_secret", lambda _service: "")
    assert routes.load_routes() == ({}, "absent")
    monkeypatch.setenv(routes.ENV_VAR, "bad")
    assert routes.load_routes() == ({}, "invalid")
    assert routes.route_names() == frozenset()


def test_import_does_not_read_keychain(monkeypatch):
    monkeypatch.setenv("SLACK_SIGNING_SECRET", "fixture")
    from webhook import auth
    calls = []
    monkeypatch.setattr(auth, "_keychain_secret", lambda service: calls.append(service) or "")
    monkeypatch.setenv(routes.ENV_VAR, "")
    importlib.reload(routes)
    assert calls == []
    assert routes.load_routes() == ({}, "absent")
    assert calls == [routes.KEYCHAIN_SERVICE]


def test_routable():
    for action, definition in ACTION_ALLOWLIST.items():
        assert routes.routable(action) == (definition[1] == "/api/v1/make" or action in ("sandbox-up", "sandbox-down")), action
    for action in ("cluster-status", "hostinger-status", "job-status", "health", "unknown"):
        assert not routes.routable(action)
    assert all(not routes.routable(a) for a in ACTION_ALLOWLIST if a.startswith("diagnose-"))


def test_escape_label():
    assert routes.escape_label("<!channel> & x>") == "&lt;!channel&gt; &amp; x&gt;"


def test_make_rejects_invalid_without_disclosure(tmp_path):
    assert tmp_path.is_dir()
    value = "privatealias:C12345678:bad"
    result = subprocess.run(["make", "update-webhook-slack-routes", f"K3DM_SLACK_NOTIFICATION_ROUTES={value}"],
                            cwd=ROOT, env={**os.environ, "HOME": str(tmp_path)}, capture_output=True, text=True)
    output = result.stdout + result.stderr
    assert result.returncode != 0
    assert "privatealias" not in output and "C12345678" not in output


def test_make_valid_map_uses_stubbed_commands(tmp_path):
    assert tmp_path.is_dir()
    stub_dir = tmp_path / "bin"
    stub_dir.mkdir()
    marker = tmp_path / "security-args"
    security = stub_dir / "security"
    security.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$ROUTE_TEST_MARKER\"\n")
    security.chmod(0o755)
    fake_make = stub_dir / "make"
    fake_make.write_text("#!/bin/sh\nexit 0\n")
    fake_make.chmod(0o755)
    real_make = shutil.which("make")
    assert real_make and security.parent == stub_dir and fake_make.parent == stub_dir
    env = {**os.environ, "HOME": str(tmp_path), "PATH": str(stub_dir) + os.pathsep + os.environ["PATH"],
           "ROUTE_TEST_MARKER": str(marker)}
    result = subprocess.run([real_make, "update-webhook-slack-routes", "K3DM_SLACK_NOTIFICATION_ROUTES=team:C12345678",
                             "MAKE=" + str(fake_make)], cwd=ROOT, env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    assert marker.read_text().splitlines() == ["add-generic-password", "-U", "-s", "k3dm-slack-notification-routes",
                                               "-a", "k3dm", "-w", "team:C12345678"]
    assert "team" not in result.stdout + result.stderr and "C12345678" not in result.stdout + result.stderr
