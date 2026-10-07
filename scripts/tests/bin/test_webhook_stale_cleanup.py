import importlib.util
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
SOURCE = ROOT / "bin" / "k3dm-webhook"
SPEC = importlib.util.spec_from_file_location(
    "k3dm_webhook_test_module", SOURCE,
    loader=SourceFileLoader("k3dm_webhook_test_module", str(SOURCE)),
)
webhook = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(webhook)


def _run(monkeypatch, tmp_path, rc, output, confirm=False, timed_out=False):
    job_id = "a1b2c3f0"
    job_dir = tmp_path / job_id
    job_dir.mkdir()
    notifications = []
    monkeypatch.setattr(webhook, "JOB_DIR", tmp_path)
    monkeypatch.setattr(webhook, "_notify_job", lambda job, text: notifications.append((job, text)))
    monkeypatch.setattr(webhook, "_redact_secrets", lambda text: text)
    monkeypatch.setattr(webhook, "_spawn_capture_text", lambda *_args, **_kwargs: (rc, output, timed_out))
    webhook._run_stale_sandbox_cleanup(job_id, confirm=confirm)
    return job_dir, notifications


def test_stale_cleanup_persists_success_and_output(monkeypatch, tmp_path):
    job_dir, notifications = _run(monkeypatch, tmp_path, 0, "already absent\n")
    assert (job_dir / "status").read_text() == "success"
    assert (job_dir / "exit_code").read_text() == "0"
    assert (job_dir / "output").read_text() == "already absent\n"
    assert "cleanup complete" in notifications[0][1].lower()


def test_stale_cleanup_persists_failure_and_exit_code(monkeypatch, tmp_path):
    job_dir, notifications = _run(monkeypatch, tmp_path, 1, "permission denied\n", confirm=True)
    assert (job_dir / "status").read_text() == "failed"
    assert (job_dir / "exit_code").read_text() == "1"
    assert (job_dir / "output").read_text() == "permission denied\n"
    assert "incomplete" in notifications[0][1].lower()
