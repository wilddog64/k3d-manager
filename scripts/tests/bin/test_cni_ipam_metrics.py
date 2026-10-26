import importlib.machinery
import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[3]
COLLECTOR = ROOT / "bin" / "k3dm-cni-ipam-metrics"
LOADER = importlib.machinery.SourceFileLoader("k3dm_cni_ipam_metrics", str(COLLECTOR))
SPEC = importlib.util.spec_from_loader("k3dm_cni_ipam_metrics", LOADER)
cni = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(cni)

STATE = """last_run=1700000000
mode=apply
kept=45
stale=207
young=0
reservations=45
range_size=254
alloc_errors_1h=2
skipped=3
skipped_oldest_age_s=4200
"""


def _run(stdout=STATE, returncode=0):
    return SimpleNamespace(stdout=stdout, stderr="", returncode=returncode)


def test_valid_state_emits_all_series(monkeypatch, capsys):
    monkeypatch.setenv("K3DM_CNI_IPAM_PUSHGATEWAY_URL", "http://127.0.0.1:9")
    monkeypatch.setattr(cni.subprocess, "run", lambda *_args, **_kwargs: _run())
    monkeypatch.setattr(sys, "argv", [str(COLLECTOR), "--dry-run"])
    assert cni.main() == 0
    output = capsys.readouterr().out
    assert "k3dm_cni_ipam_reservations{host=\"hostinger\"} 45" in output
    assert "k3dm_cni_ipam_range_size{host=\"hostinger\"} 254" in output
    assert "k3dm_cni_ipam_stale_last_run{host=\"hostinger\"} 207" in output
    assert "k3dm_cni_ipam_alloc_errors_1h{host=\"hostinger\"} 2" in output
    assert "k3dm_cni_ipam_sweep_last_run_timestamp_seconds{host=\"hostinger\"} 1700000000" in output
    assert "k3dm_cni_ipam_probe_success{host=\"hostinger\"} 1" in output
    assert "k3dm_cni_ipam_kept{host=\"hostinger\"} 45" in output
    assert "k3dm_cni_ipam_young{host=\"hostinger\"} 0" in output
    assert "k3dm_cni_ipam_skipped{host=\"hostinger\"} 3" in output
    assert "k3dm_cni_ipam_skipped_oldest_age_seconds{host=\"hostinger\"} 4200" in output



def test_remote_command_reads_the_state_file(monkeypatch):
    calls = []

    def fake_run(command, **_kwargs):
        calls.append(command)
        return _run()

    monkeypatch.setattr(cni.subprocess, "run", fake_run)
    cni._read_state()
    assert calls[0][-2:] == ["cat", "/var/lib/k3dm/cni-ipam-sweep.state"]

def test_ssh_failure_emits_only_probe_failure(monkeypatch, capsys):
    monkeypatch.setenv("K3DM_CNI_IPAM_PUSHGATEWAY_URL", "http://127.0.0.1:9")
    monkeypatch.setattr(cni.subprocess, "run", lambda *_args, **_kwargs: _run("", 255))
    monkeypatch.setattr(sys, "argv", [str(COLLECTOR), "--dry-run"])
    assert cni.main() == 0
    assert capsys.readouterr().out == 'k3dm_cni_ipam_probe_success{host="hostinger"} 0\n'


def test_non_integer_and_missing_key_emit_only_probe_failure(monkeypatch, capsys):
    monkeypatch.setenv("K3DM_CNI_IPAM_PUSHGATEWAY_URL", "http://127.0.0.1:9")
    bad = STATE.replace("stale=207", "stale=nope")
    monkeypatch.setattr(cni.subprocess, "run", lambda *_args, **_kwargs: _run(bad))
    monkeypatch.setattr(sys, "argv", [str(COLLECTOR), "--dry-run"])
    assert cni.main() == 0
    assert capsys.readouterr().out == 'k3dm_cni_ipam_probe_success{host="hostinger"} 0\n'
    monkeypatch.setattr(cni.subprocess, "run", lambda *_args, **_kwargs: _run(STATE.replace("range_size=254\n", "")))
    assert cni.main() == 0
    assert capsys.readouterr().out == 'k3dm_cni_ipam_probe_success{host="hostinger"} 0\n'


def test_old_format_state_is_valid_without_optional_keys(monkeypatch, capsys):
    monkeypatch.setenv("K3DM_CNI_IPAM_PUSHGATEWAY_URL", "http://127.0.0.1:9")
    old_state = STATE.replace("skipped=3\nskipped_oldest_age_s=4200\n", "")
    monkeypatch.setattr(cni.subprocess, "run", lambda *_args, **_kwargs: _run(old_state))
    monkeypatch.setattr(sys, "argv", [str(COLLECTOR), "--dry-run"])
    assert cni.main() == 0
    output = capsys.readouterr().out
    assert 'k3dm_cni_ipam_probe_success{host="hostinger"} 1' in output
    assert "k3dm_cni_ipam_skipped" not in output


def test_non_digit_optional_key_emits_probe_failure(monkeypatch, capsys):
    monkeypatch.setenv("K3DM_CNI_IPAM_PUSHGATEWAY_URL", "http://127.0.0.1:9")
    invalid_state = STATE.replace("skipped=3", "skipped=nope")
    monkeypatch.setattr(cni.subprocess, "run", lambda *_args, **_kwargs: _run(invalid_state))
    monkeypatch.setattr(sys, "argv", [str(COLLECTOR), "--dry-run"])
    assert cni.main() == 0
    assert capsys.readouterr().out == 'k3dm_cni_ipam_probe_success{host="hostinger"} 0\n'


def test_push_failure_is_non_fatal(monkeypatch, capsys):
    monkeypatch.setenv("K3DM_CNI_IPAM_PUSHGATEWAY_URL", "http://127.0.0.1:9")
    monkeypatch.setattr(cni.urllib.request, "urlopen", lambda *_args, **_kwargs: (_ for _ in ()).throw(OSError("offline")))
    monkeypatch.setattr(cni.time, "sleep", lambda *_args: None)
    assert cni.publish("metric 1\n") is False
    assert "push skipped (non-fatal)" in capsys.readouterr().err


def test_dry_run_does_not_push(monkeypatch, capsys):
    monkeypatch.setenv("K3DM_CNI_IPAM_PUSHGATEWAY_URL", "http://127.0.0.1:9")
    monkeypatch.setattr(cni.subprocess, "run", lambda *_args, **_kwargs: _run())
    monkeypatch.setattr(cni.urllib.request, "urlopen", lambda *_args, **_kwargs: (_ for _ in ()).throw(AssertionError("pushed")))
    monkeypatch.setattr(sys, "argv", [str(COLLECTOR), "--dry-run"])
    assert cni.main() == 0
    assert "probe_success" in capsys.readouterr().out
