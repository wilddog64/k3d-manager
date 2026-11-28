"""Approval-pending wait behavior for the cloud request helper."""

import importlib.machinery
import importlib.util
import json
from datetime import datetime, timezone
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[3]
LOADER = importlib.machinery.SourceFileLoader("cloud_request_wait", str(ROOT / "bin" / "k3dm-cloud-request"))
SPEC = importlib.util.spec_from_loader("cloud_request_wait", LOADER)
helper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(helper)


class Harness:
    def __init__(self, monkeypatch, *, pending=None, response_at=None, final=None, response_status="ok"):
        self.mono = 0.0
        self.wall = datetime(2026, 11, 25, tzinfo=timezone.utc).timestamp()
        self.pending = pending
        self.response_at = response_at
        self.final = final
        self.response_status = response_status
        self.git_calls = []
        monkeypatch.setattr(helper, "_commit_request", lambda *_: None)
        class FixedDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                return cls(2026, 11, 25, tzinfo=timezone.utc)
        monkeypatch.setattr(helper, "datetime", FixedDatetime)
        monkeypatch.setattr(helper.time, "monotonic", lambda: self.mono)
        monkeypatch.setattr(helper.time, "time", lambda: self.wall)
        monkeypatch.setattr(helper.time, "sleep", self.sleep)
        monkeypatch.setattr(helper, "_git", self.git)
        self.git_stub = helper._git

    def sleep(self, seconds):
        self.mono += seconds
        self.wall += seconds

    def git(self, args, **_kwargs):
        self.git_calls.append(args)
        assert args[0] in {"fetch", "show"}
        if args[0] == "fetch":
            return ""
        path = args[1].split(":", 1)[1]
        if path.endswith(".pending.json"):
            if self.pending is None:
                raise RuntimeError("missing pending")
            return json.dumps(self.pending)
        if path.endswith(".final.json"):
            if self.final is None:
                raise RuntimeError("missing final")
            return json.dumps(self.final)
        if self.response_at is not None and self.mono >= self.response_at:
            if self.response_status == "rejected":
                return json.dumps({"status": "rejected", "body": {"message": "denied by the operator"}})
            return json.dumps({"status": self.response_status, "body": {"status": "queued", "job_id": "a" * 8}})
        raise RuntimeError("missing response")


def pending_for(request_id, *, action="make-test-pytest", approval_id="c1-0123abcd", expires_at="2026-11-25T21:30:00Z"):
    return {"schema": 1, "id": request_id, "action": action, "status": "ok", "http_status": 202,
            "body": {"status": "approval-pending", "approval_id": approval_id, "expires_at": expires_at}}


def run(monkeypatch, harness, *, wait_final=False, timeout=300):
    # Target assertion: only the expected isolated helper harness is used; its git stub
    # and both clocks are explicitly installed before invoking main.
    assert helper._git is harness.git_stub
    assert helper.time.monotonic() == 0.0
    assert helper.time.time() == datetime(2026, 11, 25, tzinfo=timezone.utc).timestamp()
    argv = ["make-test-pytest", "--wait-final" if wait_final else "--wait", "--timeout", str(timeout), "--poll-interval", "60"]
    return helper.main(argv)


def test_no_pending_times_out_without_changing_output(monkeypatch, capsys):
    h = Harness(monkeypatch, response_at=None)
    assert run(monkeypatch, h, timeout=120) == 5
    out = capsys.readouterr()
    assert out.out == "20261125T000000Z-make-test-pytest\n"
    assert "awaiting operator approval" not in out.err
    assert h.mono == 120


def test_pending_then_answer_prints_only_notice_and_response(monkeypatch, capsys):
    h = Harness(monkeypatch, pending=pending_for("20261125T000000Z-make-test-pytest"), response_at=600)
    assert run(monkeypatch, h, timeout=300) == 0
    out = capsys.readouterr()
    assert out.out.splitlines() == ["20261125T000000Z-make-test-pytest",
                                    json.dumps({"status": "ok", "body": {"status": "queued", "job_id": "a" * 8}}, sort_keys=True)]
    assert out.err == "awaiting operator approval (c1-0123abcd) until 2026-11-25T21:30:00Z\n"


def test_twenty_minute_expiry_extends_wait_past_ten_minutes(monkeypatch):
    from datetime import timedelta
    expires_at = (datetime(2026, 11, 25, tzinfo=timezone.utc) + timedelta(seconds=1200)).isoformat()
    h = Harness(monkeypatch, pending=pending_for("20261125T000000Z-make-test-pytest", expires_at=expires_at))
    assert run(monkeypatch, h, timeout=300) == 5
    assert h.mono == 1320


@pytest.mark.parametrize("expires_delta,timeout,expected", [(10800, 300, 2100), (3600, 3600, 3600)])
def test_pending_deadline_is_capped_and_never_shortens_timeout(monkeypatch, expires_delta, timeout, expected):
    from datetime import timedelta
    expires_at = (datetime(2026, 11, 25, tzinfo=timezone.utc) + timedelta(seconds=expires_delta)).isoformat()
    h = Harness(monkeypatch, pending=pending_for("20261125T000000Z-make-test-pytest", expires_at=expires_at))
    assert run(monkeypatch, h, timeout=timeout) == 5
    assert h.mono == expected


def test_wait_final_receives_full_timeout_after_approval_wait(monkeypatch, capsys):
    h = Harness(monkeypatch, pending=pending_for("20261125T000000Z-make-test-pytest"), response_at=600)
    # Final arrives only after another complete timeout from response arrival.
    h.final = {"status": "ok", "body": {"status": "success"}}
    original_git = h.git

    def git(args, **kwargs):
        if args[0] == "show" and args[1].endswith(".final.json") and h.mono < 900:
            raise RuntimeError("missing final")
        return original_git(args, **kwargs)

    monkeypatch.setattr(helper, "_git", git)
    h.git_stub = git
    assert run(monkeypatch, h, wait_final=True, timeout=300) == 0
    out = capsys.readouterr()
    assert out.out.count("\n") == 3
    assert h.mono == 900


def test_final_rejection_keeps_existing_exit_code(monkeypatch, capsys):
    h = Harness(monkeypatch, response_at=0,
                 final={"status": "rejected", "body": {"message": "denied by the operator"}})
    assert run(monkeypatch, h, wait_final=True, timeout=300) == 3
    assert "denied by the operator" in capsys.readouterr().out


@pytest.mark.parametrize("change", [
    {"id": "wrong"}, {"action": "sandbox-up"}, {"body": {"approval_id": "bad"}},
    {"body": {"expires_at": "not a date"}},
])
def test_invalid_pending_is_absent(monkeypatch, change):
    value = pending_for("20261125T000000Z-make-test-pytest")
    if "body" in change:
        value["body"].update(change["body"])
    else:
        value.update(change)
    h = Harness(monkeypatch, pending=value)
    assert run(monkeypatch, h, timeout=120) == 5
    assert h.mono == 120
