import importlib.machinery
import importlib.util
import os
import stat
import subprocess
import sys
from pathlib import Path
from types import ModuleType, SimpleNamespace

import pytest


ROOT = Path(__file__).resolve().parents[3]
COLLECTOR = ROOT / "bin" / "k3dm-disk-metrics"
if COLLECTOR.exists():
    LOADER = importlib.machinery.SourceFileLoader("k3dm_disk_metrics", str(COLLECTOR))
    SPEC = importlib.util.spec_from_loader("k3dm_disk_metrics", LOADER)
    disk = importlib.util.module_from_spec(SPEC)
    LOADER.exec_module(disk)
else:
    disk = ModuleType("k3dm_disk_metrics")


def _run(stdout="Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/x 100 40 60 40% /x\n", returncode=0):
    return SimpleNamespace(stdout=stdout, stderr="", returncode=returncode)


def test_local_and_ssh_targets_parse_to_metrics(monkeypatch, capsys):
    calls = []
    monkeypatch.setenv("K3DM_DISK_TARGETS", "m4=local:/data m2=m2jump:k3d-snapshots")
    monkeypatch.setattr(disk.subprocess, "run", lambda command, **kwargs: calls.append(command) or _run())
    monkeypatch.setattr(sys, "argv", [str(ROOT / "bin/k3dm-disk-metrics"), "--dry-run"])

    assert disk.main() == 0
    output = capsys.readouterr().out
    assert 'k3dm_disk_size_bytes{host="m4",path="/data"} 102400' in output
    assert 'k3dm_disk_avail_bytes{host="m2",path="k3d-snapshots"} 61440' in output
    assert 'k3dm_disk_probe_success{host="m4",path="/data"} 1' in output
    assert calls[0] == ["df", "-Pk", "/data"]
    assert calls[1] == ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "--",
                        "m2jump", "df", "-Pk", "k3d-snapshots"]


def test_ssh_failure_emits_only_probe_failure_and_exits_zero(monkeypatch, capsys):
    monkeypatch.setenv("K3DM_DISK_TARGETS", "m2=m2jump:k3d-snapshots")
    monkeypatch.setattr(disk.subprocess, "run", lambda *_args, **_kwargs: _run("", 255))
    monkeypatch.setattr(sys, "argv", ["k3dm-disk-metrics", "--dry-run"])

    assert disk.main() == 0
    output = capsys.readouterr().out
    assert 'k3dm_disk_probe_success{host="m2",path="k3d-snapshots"} 0' in output
    assert "k3dm_disk_size_bytes" not in output
    assert "k3dm_disk_avail_bytes" not in output


def test_malformed_df_output_is_a_probe_failure(monkeypatch, capsys):
    monkeypatch.setenv("K3DM_DISK_TARGETS", "m4=local:/data")
    monkeypatch.setattr(disk.subprocess, "run", lambda *_args, **_kwargs: _run("header\nnot enough\n"))
    monkeypatch.setattr(sys, "argv", ["k3dm-disk-metrics", "--dry-run"])

    assert disk.main() == 0
    assert "probe_success{host=\"m4\",path=\"/data\"} 0" in capsys.readouterr().out


def test_push_failure_is_non_fatal(monkeypatch, capsys):
    monkeypatch.setattr(disk.urllib.request, "urlopen", lambda *_args, **_kwargs: (_ for _ in ()).throw(OSError("offline")))
    monkeypatch.setattr(disk.time, "sleep", lambda *_args: None)

    assert disk.publish("metric 1\n") is False
    assert "push skipped (non-fatal)" in capsys.readouterr().err


def test_default_m2_target_is_the_snapshot_dir(monkeypatch):
    monkeypatch.setattr(disk.subprocess, "run", lambda *_args, **_kwargs: _run("m5-air\n"))
    monkeypatch.delenv("K3DM_DISK_TARGETS", raising=False)
    assert ("m2", "m2jump", "k3dm-snapshots") in disk._targets()


def test_default_targets_include_hostinger_root(monkeypatch):
    monkeypatch.setattr(disk.subprocess, "run", lambda *_args, **_kwargs: _run("m5-air\n"))
    monkeypatch.delenv("K3DM_DISK_TARGETS", raising=False)
    assert ("hostinger", "hostinger", "/") in disk._targets()


def test_hostinger_probe_uses_key_user_and_host(monkeypatch, capsys):
    calls = []
    monkeypatch.setenv("HOSTINGER_SSH_USER", "u")
    monkeypatch.setenv("HOSTINGER_HOST", "h.example")
    monkeypatch.setenv("HOSTINGER_SSH_KEY", "/k")
    monkeypatch.setenv("K3DM_DISK_TARGETS", "hostinger=hostinger:/")
    monkeypatch.setattr(disk.subprocess, "run", lambda command, **kwargs: calls.append(command) or _run())
    monkeypatch.setattr(sys, "argv", [str(ROOT / "bin/k3dm-disk-metrics"), "--dry-run"])

    assert disk.main() == 0
    output = capsys.readouterr().out
    command = calls[0]
    assert "-i" in command
    assert "/k" in command
    assert "IdentitiesOnly=yes" in command
    assert command[command.index("--") + 1] == "u@h.example"
    assert command[-3:] == ["df", "-Pk", "/"]
    assert 'k3dm_disk_probe_success{host="hostinger",path="/"} 1' in output


def test_fleet_defaults_and_override(monkeypatch):
    calls = []
    def scutil(command, **kwargs):
        calls.append(command)
        return _run("m5-air\n")
    monkeypatch.setattr(disk.subprocess, "run", scutil)
    monkeypatch.delenv("K3DM_DISK_TARGETS", raising=False)
    assert disk._targets() == [("m5", "local", "/System/Volumes/Data"),
                               ("m2", "m2jump", "k3dm-snapshots"),
                               ("m4", "m4-air.local", "/System/Volumes/Data"),
                               ("hostinger", "hostinger", "/")]
    assert calls == [["/usr/sbin/scutil", "--get", "LocalHostName"]]  # agent-audit: allow assert-removed bare scutil replaced by its absolute path
    monkeypatch.setenv("K3DM_DISK_TARGETS", "custom=local:/custom")
    assert disk._targets() == [("custom", "local", "/custom")]
    assert len(calls) == 1


def test_m4_defaults_exclude_self(monkeypatch):
    monkeypatch.delenv("K3DM_DISK_TARGETS", raising=False)
    monkeypatch.setattr(disk.subprocess, "run", lambda *_args, **_kwargs: _run("m4-air\n"))
    targets = disk._targets()
    assert ("m4", "local", "/System/Volumes/Data") in targets
    assert ("m5", "m5-air.local", "/System/Volumes/Data") in targets
    assert not any(host == "m4-air.local" for _, host, _ in targets)


@pytest.mark.skipif(not Path("/usr/sbin/scutil").exists(), reason="macOS only: needs /usr/sbin/scutil")
def test_launchd_path_dry_run_uses_local_hostname_and_ssh_stub(tmp_path):
    stub_dir = tmp_path / "bin"
    stub_dir.mkdir()
    ssh_stub = stub_dir / "ssh"
    ssh_stub.write_text("#!/bin/sh\nexit 0\n")
    ssh_stub.chmod(ssh_stub.stat().st_mode | stat.S_IXUSR)
    env = os.environ.copy()
    env.pop("K3DM_DISK_TARGETS", None)
    env["PATH"] = f"{stub_dir}:/usr/bin:/bin"
    result = subprocess.run([sys.executable, str(COLLECTOR), "--dry-run"], env=env,
                            capture_output=True, text=True, check=False)
    assert env["PATH"] == f"{stub_dir}:/usr/bin:/bin"
    assert result.returncode == 0, result.stderr
    local_name = subprocess.run(["/usr/sbin/scutil", "--get", "LocalHostName"],
                                capture_output=True, text=True, check=True).stdout.strip().removesuffix("-air")
    assert f'k3dm_disk_probe_success{{host="{local_name}",path="/System/Volumes/Data"}}' in result.stdout


def test_no_bare_scutil_command(monkeypatch):
    calls = []
    monkeypatch.setattr(disk.subprocess, "run",
                        lambda command, **kwargs: calls.append(command) or _run("m5-air\n"))
    monkeypatch.delenv("K3DM_DISK_TARGETS", raising=False)
    disk._targets()
    assert calls
    assert all(command[0] != "scutil" for command in calls)


def test_hermes_disk_publish_reports_failure_but_not_success(monkeypatch, capsys):
    hermes_path = ROOT / "bin" / "k3dm-hermes"
    hermes_spec = importlib.util.spec_from_loader(
        "k3dm_hermes_disk_metrics_test",
        importlib.machinery.SourceFileLoader("k3dm_hermes_disk_metrics_test", str(hermes_path)))
    hermes = importlib.util.module_from_spec(hermes_spec)
    hermes_spec.loader.exec_module(hermes)
    results = [SimpleNamespace(returncode=0, stderr=""),
               SimpleNamespace(returncode=1, stderr="first\n" + "z" * 400 + "\n")]
    calls = []

    def run(command, **kwargs):
        calls.append(kwargs)
        return results.pop(0)

    monkeypatch.setattr(hermes.subprocess, "run", run)
    hermes._publish_disk_metrics()
    assert capsys.readouterr().err == ""
    hermes._publish_disk_metrics()
    output = capsys.readouterr().err
    assert output == "disk metrics publish failed: rc=1: " + "z" * 300 + "\n"
    assert len(output.rstrip("\n")) <= len("disk metrics publish failed: rc=1: ") + 300
    assert all(call["check"] is False and call["timeout"] == 120 for call in calls)
