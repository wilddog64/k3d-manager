"""`/api/v1/make` jobs write their output file, scrubbed, before the terminal status.

docs/bugs/2026-09-28-make-jobs-never-write-output-file.md
"""

import sys
import threading
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

from webhook import lifecycle  # noqa: E402


@pytest.fixture
def job(tmp_path, monkeypatch):
    job_id = "abcd1234"
    (tmp_path / job_id).mkdir()
    lock = threading.Lock()
    lock.acquire()
    monkeypatch.setattr(lifecycle, "JOB_DIR", tmp_path)
    monkeypatch.setattr(lifecycle, "_notify_job", lambda *_a, **_k: None)
    monkeypatch.setattr(lifecycle, "_redact_secrets", lambda text: text)
    monkeypatch.setattr(lifecycle, "_helpers", {"make_job_lock": lock})
    return tmp_path / job_id


def _run(job, monkeypatch, rc, output):
    seen = {}

    def fake_spawn(_cmd, output_path, **_k):
        Path(output_path).write_text(output)
        return 4242

    monkeypatch.setattr(lifecycle, "_spawn_job", fake_spawn)
    monkeypatch.setattr(lifecycle.os, "waitpid", lambda *_a: (4242, rc << 8))

    real_write = Path.write_text

    def spy_write(self, data, *a, **k):
        if self.name == "status" and data != "running":
            seen["output_at_status"] = (job / "make.log").exists()
        return real_write(self, data, *a, **k)

    monkeypatch.setattr(lifecycle, "_spawn_capture_text", fake_spawn)
    monkeypatch.setattr(Path, "write_text", spy_write)
    lifecycle._run_make_target(job.name, ["fix-list"], 60, "cloud-bridge")
    return seen


def test_make_job_output_is_written(job, monkeypatch):
    _run(job, monkeypatch, 0, "fix-status\nfix-delete-pod\n")
    assert (job / "make.log").read_text() == "fix-status\nfix-delete-pod\n"
    assert (job / "status").read_text() == "success"


def test_output_exists_before_terminal_status(job, monkeypatch):
    seen = _run(job, monkeypatch, 2, "boom\n")
    assert seen["output_at_status"] is True
    assert (job / "status").read_text() == "failed"


def test_make_job_log_keeps_local_command_output(job, monkeypatch):
    _run(job, monkeypatch, 1, "Authorization: Bearer make-synthetic-token\nDB_PASSWORD=hunter2-synthetic\n")
    written = (job / "make.log").read_text()
    assert "make-synthetic-token" in written
    assert "hunter2-synthetic" in written
    assert not (job / "output").exists()
    note = (job / "failure.md").read_text()
    assert "hunter2-synthetic" not in note
    assert "[REDACTED]" in note or "***REDACTED***" in note


def test_successful_make_job_writes_no_failure_note(job, monkeypatch):
    _run(job, monkeypatch, 0, "all good\n")
    assert not (job / "failure.md").exists()


def test_make_job_exports_its_junit_report_path(job, monkeypatch):
    seen = {}

    def fake_spawn(_cmd, output_path, **kwargs):
        seen["env"] = kwargs.get("env") or {}
        Path(output_path).write_text("")
        return 4242

    monkeypatch.setattr(lifecycle, "_spawn_job", fake_spawn)
    monkeypatch.setattr(lifecycle.os, "waitpid", lambda *_a: (4242, 0))
    lifecycle._run_make_target(job.name, ["test-pytest"], 60, "cloud-bridge")
    assert seen["env"]["K3DM_JUNIT_XML"] == str(job / "junit.xml")
