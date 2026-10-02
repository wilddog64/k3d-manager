"""Offline tests for the webhook and cloud-bridge restart targets."""

import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MAKEFILE = ROOT / "Makefile"


def _recipe(target):
    lines = MAKEFILE.read_text().splitlines()
    start = lines.index(f"{target}:")
    body = []
    for line in lines[start + 1:]:
        if not line.startswith("\t"):
            break
        body.append(line)
    return "\n".join(body)


def test_restart_webhook_also_invokes_cloud_bridge():
    assert "restart-cloud-bridge" in _recipe("restart-webhook")


def test_restart_cloud_bridge_targets_its_launchagent():
    recipe = _recipe("restart-cloud-bridge")
    assert "com.k3d-manager.cloud-bridge" in recipe
    assert "kickstart -k" in recipe


def test_restart_cloud_bridge_skips_an_uninstalled_bridge(tmp_path):
    home = tmp_path / "home"
    stub_dir = tmp_path / "bin"
    stub_dir.mkdir()
    calls = tmp_path / "launchctl.calls"
    (stub_dir / "launchctl").write_text(f"#!/bin/sh\nprintf '%s\\n' \"$*\" >> '{calls}'\n")
    (stub_dir / "launchctl").chmod(0o755)
    result = subprocess.run(
        ["make", "-C", str(ROOT), "restart-cloud-bridge", f"HOME={home}"],
        env={**os.environ, "PATH": f"{stub_dir}{os.pathsep}{os.environ['PATH']}"},
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0
    assert "not installed — skipping" in result.stderr
    assert not calls.exists()


def test_restart_cloud_bridge_calls_stub_when_plist_exists(tmp_path):
    home = tmp_path / "home"
    plist = home / "Library" / "LaunchAgents" / "com.k3d-manager.cloud-bridge.plist"
    plist.parent.mkdir(parents=True)
    plist.touch()
    stub_dir = tmp_path / "bin"
    stub_dir.mkdir()
    calls = tmp_path / "launchctl.calls"
    (stub_dir / "launchctl").write_text(f"#!/bin/sh\nprintf '%s\\n' \"$*\" >> '{calls}'\n")
    (stub_dir / "launchctl").chmod(0o755)
    result = subprocess.run(
        ["make", "-C", str(ROOT), "restart-cloud-bridge", f"HOME={home}"],
        env={**os.environ, "PATH": f"{stub_dir}{os.pathsep}{os.environ['PATH']}"},
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0
    assert calls.read_text().strip().endswith("com.k3d-manager.cloud-bridge")
