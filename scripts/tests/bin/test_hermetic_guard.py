import os
import shutil
import socket
import subprocess
from pathlib import Path

import pytest

def test_real_security_is_blocked():
    if os.environ.get("K3DM_HERMETIC") == "report":
        pytest.skip("enforce-only guard assertion")
    resolved = shutil.which("security") or ""
    if any(part.startswith("k3dm-tripwire.") for part in Path(resolved).parts):
        pytest.skip("tripwire replaces the executable in make test-pytest")
    with pytest.raises(RuntimeError, match=r"security.*executable"):
        subprocess.run(["security", "help"], check=False)


def test_temp_path_stub_uses_call_environment(tmp_path, capfd):
    stub = tmp_path / "kubectl"
    stub.write_text("#!/bin/sh\nprintf stub\n")
    stub.chmod(0o755)
    subprocess.run(["kubectl", "version"], env={"PATH": str(tmp_path)}, check=True)
    assert capfd.readouterr().out == "stub"


@pytest.mark.skipif(not os.path.exists("/usr/bin/security"), reason="security is absent on Linux")
def test_absolute_security_is_blocked():
    if os.environ.get("K3DM_HERMETIC") == "report":
        pytest.skip("enforce-only guard assertion")
    with pytest.raises(RuntimeError, match=r"security.*executable"):
        subprocess.run(["/usr/bin/security", "help"], check=False)


def test_local_git_operations_are_allowed(tmp_path):
    env = {**os.environ, "HOME": str(tmp_path), "GIT_CONFIG_NOSYSTEM": "1"}
    subprocess.run(["git", "init"], cwd=tmp_path, env=env, check=True, capture_output=True)
    (tmp_path / "file").write_text("content\n")
    subprocess.run(["git", "add", "file"], cwd=tmp_path, env=env, check=True)
    subprocess.run(
        ["git", "-c", "user.name=test", "-c", "user.email=test@example.invalid", "commit", "-m", "test"],
        cwd=tmp_path,
        env=env,
        check=True,
        capture_output=True,
    )
    subprocess.run(["git", "log", "-1"], cwd=tmp_path, env=env, check=True, capture_output=True)


def test_remote_git_is_blocked():
    if os.environ.get("K3DM_HERMETIC") == "report":
        pytest.skip("enforce-only guard assertion")
    with pytest.raises(RuntimeError, match=r"git.*git-remote"):
        subprocess.run(["git", "ls-remote", "https://example.invalid/x.git"], check=False)


def test_network_blocks_non_loopback_and_allows_loopback():
    if os.environ.get("K3DM_HERMETIC") == "report":
        pytest.skip("enforce-only guard assertion")
    with pytest.raises(RuntimeError, match=r"network"):
        socket.create_connection(("192.0.2.1", 80), timeout=0.1)
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    client = socket.create_connection(listener.getsockname(), timeout=0.1)
    client.close()
    listener.close()


@pytest.mark.external(reason="verifies the opt-out marker with a temporary executable")
def test_external_marker_allows_temp_stub_and_absolute_call(tmp_path):
    stub = tmp_path / "security"
    stub.write_text("#!/bin/sh\nexit 0\n")
    stub.chmod(0o755)
    env = {"PATH": str(tmp_path)}
    subprocess.run(["security", "help"], env=env, check=True)
    subprocess.run([str(stub), "help"], check=True)


def test_report_mode_records_violation(monkeypatch, tmp_path):
    monkeypatch.setenv("K3DM_HERMETIC", "report")
    stub = tmp_path / "security"
    stub.write_text("#!/bin/sh\nexit 0\n")
    stub.chmod(0o755)
    monkeypatch.setattr(
        "shutil.which", lambda command, path=None: "/usr/bin/security"
    )
    subprocess.run(["security", "help"], env={"PATH": str(tmp_path)}, check=True)
