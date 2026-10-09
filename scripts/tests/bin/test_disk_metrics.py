import importlib.machinery
import importlib.util
import sys
from pathlib import Path
from types import ModuleType, SimpleNamespace


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
    monkeypatch.delenv("K3DM_DISK_TARGETS", raising=False)
    assert ("m2", "m2jump", "k3dm-snapshots") in disk._targets()
