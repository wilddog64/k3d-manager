import importlib.util
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

_WEBHOOK = ROOT / "bin" / "k3dm-webhook"
_spec = importlib.util.spec_from_file_location(
    "k3dm_webhook_thread_actor", _WEBHOOK,
    loader=SourceFileLoader("k3dm_webhook_thread_actor", str(_WEBHOOK)),
)
wh = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wh)


class _ImmediateThread:
    def __init__(self, *, target, args=(), kwargs=None, daemon=None):
        self.target = target
        self.args = args
        self.kwargs = kwargs or {}

    def start(self):
        self.target(*self.args, **self.kwargs)


@pytest.fixture
def thread_env(monkeypatch, tmp_path):
    monkeypatch.setattr(wh, "JOB_DIR", tmp_path)
    (tmp_path / "parent").mkdir()
    monkeypatch.setattr(wh.threading, "Thread", _ImmediateThread)
    monkeypatch.setattr(wh, "_notify_job", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(wh, "_MAKE_JOB_LOCK", __import__("threading").Lock())
    monkeypatch.setattr(wh, "_role_allows", lambda _actual, _required: True)


def test_known_user_is_make_job_actor(thread_env, monkeypatch):
    calls = []
    monkeypatch.setattr(wh, "_run_make_target", lambda *args: calls.append(args))

    wh._handle_thread_command("parent", "k3dm test-all", "admin", "C1", "U123")

    assert calls[0][-1] == "slack-thread:U123"


def test_missing_user_keeps_role_actor(thread_env, monkeypatch):
    calls = []
    monkeypatch.setattr(wh, "_run_make_target", lambda *args: calls.append(args))

    wh._handle_thread_command("parent", "k3dm test-all", "admin", "C1")

    assert calls[0][-1] == "slack-thread:admin"


def test_refused_thread_command_audits_known_user(thread_env, monkeypatch):
    audits = []
    monkeypatch.setattr(wh, "_role_allows", lambda _actual, _required: False)
    monkeypatch.setattr(wh, "_audit_remote_action", lambda *args, **kwargs: audits.append((args, kwargs)))

    wh._handle_thread_command("parent", "kill", "reader", "C1", "U123")

    assert audits[0][0][2] == "slack-thread:U123"
    assert audits[0][0][3] == "reader"


def test_user_id_does_not_change_role_permission(thread_env, monkeypatch):
    calls = []
    monkeypatch.setattr(wh, "_role_allows", lambda actual, required: actual == "admin")
    monkeypatch.setattr(wh, "_run_make_target", lambda *args: calls.append(args))

    wh._handle_thread_command("parent", "k3dm test-all", "reader", "C1", "U123")

    assert calls == []


def test_actor_contains_no_command_text_or_secret(thread_env, monkeypatch):
    calls = []
    monkeypatch.setattr(wh, "_run_make_target", lambda *args: calls.append(args))

    wh._handle_thread_command("parent", "k3dm test-all confirm", "admin", "C1", "U123")

    actor = calls[0][-1]
    assert actor == "slack-thread:U123"
    assert "test-all" not in actor
    assert "secret" not in actor
