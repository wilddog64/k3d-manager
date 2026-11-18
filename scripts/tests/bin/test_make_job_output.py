"""`/api/v1/make` jobs write their output file, scrubbed, before the terminal status.

docs/bugs/2026-09-28-make-jobs-never-write-output-file.md
"""

import os
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


def test_make_job_persists_exit_code_for_status_api(job, monkeypatch):
    _run(job, monkeypatch, 2, "boom\n")
    assert (job / "exit_code").read_text() == "2"


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


def test_cluster_output_excerpt_tildifies_traceback(job, monkeypatch):
    monkeypatch.setenv("HOME", "/Users/k3dm-fake-home")
    assert os.environ["HOME"] == "/Users/k3dm-fake-home"
    output_path = job / "output"
    output_path.write_text(
        'Traceback (most recent call last):\n'
        '  File "/Users/k3dm-fake-home/src/k3d-manager/scripts/lib/webhook/lifecycle.py", '
        'line 415, in _run_cluster\n'
    )
    excerpt = lifecycle._cluster_output_excerpt(output_path, lambda text: text)
    assert 'File "~/src/k3d-manager/' in excerpt
    assert "/Users/k3dm-fake-home" not in excerpt


def test_make_job_result_post_is_sanitized(job, monkeypatch):
    monkeypatch.setenv("HOME", "/Users/k3dm-fake-home")
    assert os.environ["HOME"] == "/Users/k3dm-fake-home"
    texts = []
    monkeypatch.setattr(lifecycle, "_notify_job", lambda _job, text: texts.append(text))
    output = "/Users/k3dm-fake-home/src/x: error\npassword=hunter2\n"
    _run(job, monkeypatch, 2, output)
    posted = texts[-1]
    assert "~/src/x: error" in posted
    assert "***REDACTED***" in posted
    assert "/Users/k3dm-fake-home" not in posted
    assert "hunter2" not in posted
    assert (job / "make.log").read_text() == output


def test_make_job_progress_post_is_sanitized(job, monkeypatch):
    monkeypatch.setenv("HOME", "/Users/k3dm-fake-home")
    assert os.environ["HOME"] == "/Users/k3dm-fake-home"
    callbacks = []
    texts = []

    class FakeTimer:
        def __init__(self, _interval, callback):
            callbacks.append(callback)

        def start(self):
            pass

        def cancel(self):
            pass

    monkeypatch.setattr(lifecycle.threading, "Timer", FakeTimer)
    monkeypatch.setattr(lifecycle, "_notify_job", lambda _job, text: texts.append(text))
    _run(job, monkeypatch, 2, "/Users/k3dm-fake-home/src/x: error\npassword=hunter2\n")
    callbacks[0]()
    posted = texts[-1]
    assert "~/src/x: error" in posted
    assert "***REDACTED***" in posted
    assert "/Users/k3dm-fake-home" not in posted
    assert "hunter2" not in posted
