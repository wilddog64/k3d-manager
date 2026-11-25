"""Named contract tests for the pure cloud approval store."""

import json
import os
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
from webhook import cloud_approval as approval


class Rand:
    def __init__(self):
        self.values = iter(["1234abcd", "0123456789abcdef"])

    def token_hex(self, _size):
        return next(self.values)


def request(expiry="2030-01-01T00:00:00Z", **extra):
    return {"action": "make-e2e", "args": {}, "requested_by": "operator", "expires_at": expiry, **extra}


def admitted(store=None, now=1795636800, req=None):
    store = store or approval.Store()
    record = approval.admit(store, "c2-abcdef12", req or request(), now, Rand())
    assert isinstance(record, approval.Pending)
    return store, record


def test_load_missing_store_is_empty(tmp_path):
    assert approval.load(tmp_path / "missing.json") == approval.Store()


@pytest.mark.parametrize("contents", ["{", '{"v":2,"pending":{},"cards":[],"last_drain":0}',
                                      '{"v":true,"pending":{},"cards":[],"last_drain":0}',
                                      '{"v":1,"pending":{"x":{"request_id":"x","approval_id":"c1-1234abcd","nonce":"bad","request":{},"created_at":1,"expires_at":2,"notice_published":false}},"cards":[],"last_drain":0}',
                                      '{"v":1,"pending":{"x":{"request_id":"x","approval_id":"c1-1234abcd","nonce":"0123456789abcdef","request":{},"created_at":1,"expires_at":2,"notice_published":0}},"cards":[],"last_drain":0}'])
def test_load_malformed_store_raises(tmp_path, contents):
    path = tmp_path / "bad.json"
    path.write_text(contents)
    with pytest.raises(approval.StoreError):
        approval.load(path)


def test_save_round_trip_permissions_and_directory_mode(tmp_path):
    path = tmp_path / "private" / "nested" / "state.json"
    store, _ = admitted(now=1795636800)
    approval.save(path, store)
    assert approval.load(path) == store
    assert path.stat().st_mode & 0o777 == 0o600
    assert path.parent.stat().st_mode & 0o777 == 0o700


def test_save_replace_failure_preserves_old_file_and_cleans_temp(tmp_path, monkeypatch):
    path = tmp_path / "state.json"
    path.write_text("old")
    store, _ = admitted(now=1795636800)
    def fail_replace(_source, _target):
        raise OSError("replace failed")
    monkeypatch.setattr(approval.os, "replace", fail_replace)
    with pytest.raises(OSError):
        approval.save(path, store)
    assert path.read_text() == "old"
    assert list(tmp_path.iterdir()) == [path]


def test_admit_idempotent_even_when_pending_cap_is_full():
    store, record = admitted(now=1795636800)
    store.pending.update({f"x{i}": record for i in range(3)})
    assert approval.admit(store, record.request_id, request(), 1795636801, Rand()) is record


def test_admit_parses_offset_expiry():
    store, record = admitted(now=1795636800, req=request("2026-11-25T13:30:00-08:00"))
    assert record.expires_at == 1795636800 + 1800
    assert len(store.cards) == 1


def test_admit_refuses_under_five_minutes():
    result = approval.admit(approval.Store(), "id", request("2026-11-25T20:04:59Z"), 1795636800, Rand())
    assert isinstance(result, approval.Refusal) and "5 minutes" in result.reason


def test_admit_clamps_to_thirty_minutes():
    _, record = admitted(now=1795636800, req=request("2026-11-26T15:00:00Z"))
    assert record.expires_at == 1795636800 + approval.MAX_LIFETIME


def test_admit_caps_pending_at_three_and_hourly_cards_at_ten_with_sliding_window():
    now = 1795636800
    store = approval.Store()
    for index in range(3):
        approval.admit(store, f"id{index}", request(), now, Rand())
    assert isinstance(approval.admit(store, "four", request(), now, Rand()), approval.Refusal)
    store = approval.Store(cards=[now - 3600.01] + [now - 10] * 9)
    assert isinstance(approval.admit(store, "eleven", request(), now, Rand()), approval.Pending)
    store.cards = [now - 10] * 10
    assert isinstance(approval.admit(store, "blocked", request(), now, Rand()), approval.Refusal)


def test_remove_drops_or_ignores_missing_id():
    store, record = admitted(now=1795636800)
    approval.remove(store, record.request_id)
    approval.remove(store, record.request_id)
    assert store.pending == {}


def test_card_escapes_and_strips_attacker_text():
    req = request(args={"a&<": "<!channel> `hi`\nsecond"})
    store, record = admitted(now=1795636800, req=req)
    text, _ = approval.card(record)
    assert "&lt;!channel&gt;" in text and "&amp;" in text
    assert "`hi`" not in text and "second" in text and "\n" not in text


@pytest.mark.parametrize("submitter", [{"x": 1}, 7, "op\n*Verified*"])
def test_card_invalid_submitter_is_safe(submitter):
    _, record = admitted(now=1795636800, req=request(requested_by=submitter))
    text, _ = approval.card(record)
    assert "requested_by: `(invalid)`" in text


def test_card_nonce_is_only_in_button_values():
    _, record = admitted(now=1795636800)
    text, blocks = approval.card(record)
    assert record.nonce not in text
    values = [element["value"] for block in blocks if block["type"] == "actions"
              for element in block["elements"]]
    assert values == [f"{record.approval_id}|{record.nonce}"] * 2


def test_card_remote_runner_and_unknown_action():
    _, record = admitted(now=1795636800, req=request(action="make-e2e-remote", args={"runner": "runner-1"}))
    assert "runner runner-1" in str(approval.card(record)[1])
    record.request["action"] = "unknown"
    with pytest.raises(ValueError):
        approval.card(record)


def test_due_for_drain_throttle():
    store, _ = admitted(now=1795636800)
    store.last_drain = 1795636800
    assert not approval.due_for_drain(store, 1795636829)
    assert approval.due_for_drain(store, 1795636830)
    assert not approval.due_for_drain(approval.Store(), 1795637000)


def test_decide_execute_and_default_decision():
    store, record = admitted(now=1795636800)
    result = approval.decide(store, [{"action_id": record.approval_id, "nonce": record.nonce,
                                     "approved_by": "U1"}], 1795636810)
    assert [entry.kind for entry in result] == ["drop", "execute"]
    assert result[1].request is record.request and store.pending == {} and store.last_drain == 1795636810


def test_decide_wrong_nonce_unknown_id_and_unknown_decision_drop():
    store, record = admitted(now=1795636800)
    result = approval.decide(store, [{"action_id": record.approval_id, "nonce": "f" * 16},
                                     {"action_id": "c9-deadbeef", "nonce": "0" * 16},
                                     {"action_id": record.approval_id, "nonce": record.nonce,
                                      "decision": "maybe"}], 1795636810)
    assert [entry.kind for entry in result] == ["drop"] * 3
    assert record.request_id in store.pending


def test_decide_expired_item_and_sweep_emit_expire():
    store, record = admitted(now=1795636800)
    record.expires_at = 1795636805
    result = approval.decide(store, [{"action_id": record.approval_id, "nonce": record.nonce}], 1795636805)
    assert [entry.kind for entry in result] == ["drop", "expire"] and store.pending == {}
    store, other = admitted(now=1795636800)
    other.expires_at = 1795636805
    assert [entry.kind for entry in approval.decide(store, [], 1795636805)] == ["expire"]


@pytest.mark.parametrize("decisions", [["approve", "deny"], ["deny", "approve"]])
def test_decide_deny_wins_in_both_orders(decisions):
    store, record = admitted(now=1795636800)
    items = [{"action_id": record.approval_id, "nonce": record.nonce, "decision": decision}
             for decision in decisions]
    result = approval.decide(store, items, 1795636810)
    assert not any(entry.kind == "execute" for entry in result)
    assert sum(entry.kind == "deny" for entry in result) == 1
    assert store.pending == {}


def test_decide_wrong_nonce_deny_does_not_override_valid_approval():
    store, record = admitted(now=1795636800)
    result = approval.decide(store, [
        {"action_id": record.approval_id, "nonce": "f" * 16, "decision": "deny"},
        {"action_id": record.approval_id, "nonce": record.nonce, "decision": "approve"},
    ], 1795636810)
    assert sum(entry.kind == "execute" for entry in result) == 1


def test_decide_double_approve_executes_once():
    store, record = admitted(now=1795636800)
    item = {"action_id": record.approval_id, "nonce": record.nonce, "decision": "approve"}
    result = approval.decide(store, [item, item], 1795636810)
    assert sum(entry.kind == "execute" for entry in result) == 1


@pytest.mark.parametrize("branch", ["unknown", "wrong_nonce", "expired", "deny", "approve", "unknown_decision"])
def test_decide_drop_carries_drained_action_id(branch):
    store, record = admitted(now=1795636800)
    item = {"action_id": record.approval_id, "nonce": record.nonce}
    if branch == "unknown":
        item.update(action_id="c9-deadbeef", nonce="0" * 16)
    elif branch == "wrong_nonce":
        item["nonce"] = "f" * 16
    elif branch == "expired":
        record.expires_at = 1795636805
    elif branch == "deny":
        item["decision"] = "deny"
    elif branch == "unknown_decision":
        item["decision"] = "maybe"

    result = approval.decide(store, [item], 1795636810)
    drop = next(entry for entry in result if entry.kind == "drop")
    assert drop.approval_id == item["action_id"]
