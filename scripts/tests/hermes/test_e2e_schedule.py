import json
import os
from datetime import datetime, timedelta

from hermes.e2e_schedule import (claim_slot, configured_schedule, due_slot,
                                 parse_schedule, pid_alive, retry_claim)


def test_due_schedule_and_marker(tmp_path):
    schedule = parse_schedule("wed,sat@02:00")
    wed = datetime(2026, 9, 16, 2, 0)
    assert due_slot(wed.replace(hour=1, minute=59), tmp_path, schedule) is None
    assert due_slot(wed, tmp_path, schedule) == "2026-09-16"
    assert due_slot(datetime(2026, 9, 17, 3), tmp_path, schedule) is None
    assert due_slot(datetime(2026, 9, 19, 23, 30), tmp_path, schedule) == "2026-09-19"
    (tmp_path / "2026-09-16.json").write_text("{}")
    assert due_slot(wed, tmp_path, schedule) is None


def test_claim_retry_parse_and_disabled(tmp_path):
    now = datetime(2026, 9, 16, 2)
    path = tmp_path / "2026-09-16.claim"
    path.write_text(json.dumps({"attempts": 6, "next_try": now.isoformat()}))
    assert due_slot(now, tmp_path, parse_schedule("wed@02:00")) is None
    path.write_text(json.dumps({"attempts": 1, "next_try": (now + timedelta(minutes=1)).isoformat()}))
    assert due_slot(now, tmp_path, parse_schedule("wed@02:00")) is None
    assert parse_schedule("wednesday@02:00") is None
    assert configured_schedule({"K3DM_HERMES_E2E_ENABLED": "0"}) is None
    path.unlink()
    assert claim_slot(tmp_path, "2026-09-16", now, pid=999999) is not None


def test_live_claim_blocks_respawn_but_a_retry_claim_does_not(tmp_path):
    now = datetime(2026, 9, 16, 2)
    path = tmp_path / "2026-09-16.claim"
    path.write_text(json.dumps({"attempts": 0, "next_try": now.isoformat(), "pid": os.getpid()}))
    assert claim_slot(tmp_path, "2026-09-16", now, pid=os.getpid()) is None
    retry_claim(tmp_path, "2026-09-16", now)
    assert json.loads(path.read_text())["pid"] == 0
    assert claim_slot(tmp_path, "2026-09-16", now, pid=12345) is not None


def test_pid_alive_rejects_zero_and_negative():
    assert pid_alive(os.getpid()) is True
    assert pid_alive(0) is False
    assert pid_alive(-1) is False
    assert pid_alive(None) is False
