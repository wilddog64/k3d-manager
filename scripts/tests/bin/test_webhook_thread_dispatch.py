import importlib.util
import threading
from importlib.machinery import SourceFileLoader
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
_WEBHOOK = ROOT / "bin" / "k3dm-webhook"
_spec = importlib.util.spec_from_file_location(
    "k3dm_webhook_thread_dispatch", _WEBHOOK,
    loader=SourceFileLoader("k3dm_webhook_thread_dispatch", str(_WEBHOOK)),
)
wh = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wh)


@pytest.fixture
def dispatch_env(monkeypatch, tmp_path):
    monkeypatch.setattr(wh, "JOB_DIR", tmp_path)
    (tmp_path / "job").mkdir()
    started = []
    notices = []

    class Thread:
        def __init__(self, *, target, args=(), kwargs=None, daemon=None):
            started.append((target, args, kwargs))

        def start(self):
            return None

    monkeypatch.setattr(wh.threading, "Thread", Thread)
    monkeypatch.setattr(wh, "_notify_job", lambda _job, text: notices.append(text))
    monkeypatch.setattr(wh, "_validate_diagnostics_request", lambda _request: None)
    monkeypatch.setattr(wh, "_run_cluster_diagnostics", lambda *args, **kwargs: None)
    monkeypatch.setattr(wh, "_run_make_target", lambda *args, **kwargs: None)
    monkeypatch.setattr(wh, "_run_upgrade_thread_job", lambda *args, **kwargs: None)
    monkeypatch.setattr(wh, "_MAKE_JOB_LOCK", threading.Lock())
    monkeypatch.setattr(wh, "_role_allows", lambda actual, required: (
        actual == "admin" or required == "reader"
    ))
    return started, notices


@pytest.mark.parametrize(
    ("command", "role"),
    [
        ("cluster-diagnose hub pods monitoring", "reader"),
        ("k3dm test-all", "admin"),
        ("argocd-upgrade 7.9.1 acg", "admin"),
    ],
)
def test_successful_new_commands_ack_once_without_unknown(dispatch_env, command, role):
    started, notices = dispatch_env

    wh._handle_thread_command("job", command, role, "C1")

    assert len(started) == 1
    assert sum("queued" in notice for notice in notices) == 1
    assert not any("Unknown command" in notice for notice in notices)


def test_kill_still_dispatches(dispatch_env, monkeypatch):
    _started, notices = dispatch_env
    monkeypatch.setattr(wh, "_running_procs", {"job": 123})
    monkeypatch.setattr(wh.os, "killpg", lambda *args: None)

    wh._handle_thread_command("job", "kill", "admin", "C1")

    assert len(notices) == 1
    assert "Kill requested" in notices[0]


def test_status_still_replies(dispatch_env):
    _started, notices = dispatch_env

    wh._handle_thread_command("job", "status", "reader", "C1")

    assert len(notices) == 1
    assert "status" in notices[0]


def test_unknown_word_still_gets_unknown_reply(dispatch_env):
    _started, notices = dispatch_env

    wh._handle_thread_command("job", "/unknown-word", "reader", "C1")

    assert len(notices) == 1
    assert "Unknown command" in notices[0]


def test_reader_k3dm_is_denied_without_worker(dispatch_env):
    started, notices = dispatch_env

    wh._handle_thread_command("job", "k3dm test-all", "reader", "C1")

    assert started == []
    assert len(notices) == 1
    assert "requires role *admin*" in notices[0]
