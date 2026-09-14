import importlib.machinery
import importlib.util
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

from hermes import approvals
from hermes.slack import post_interactive

loader = importlib.machinery.SourceFileLoader("k3dm_hermes", str(ROOT / "bin" / "k3dm-hermes"))
spec = importlib.util.spec_from_loader("k3dm_hermes", loader)
k3dm_hermes = importlib.util.module_from_spec(spec)
loader.exec_module(k3dm_hermes)


class FakeResponse:
    def __init__(self, body=b"[]"):
        self.body = body

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self):
        return self.body


def fake_opener(calls, body=b"[]"):
    def opener(request, timeout):
        calls.append((request.full_url, request.get_method(), dict(request.header_items()), request.data))
        return FakeResponse(body)
    return opener


def valid_item():
    return {"action_id": "r2-0123abcd", "nonce": "0123456789abcdef", "approved_by": "UAPPROVER1"}


def test_fetch_approvals_fails_closed_without_usable_transport():
    calls = []
    for url, token in [("", "tok"), ("https://relay", ""), ("http://relay", "tok")]:
        assert approvals.fetch_approvals(url, token, fake_opener(calls)) == []
    assert calls == []


def test_fetch_approvals_fails_closed_on_error_or_non_list():
    assert approvals.fetch_approvals("https://relay", "tok", lambda *_args, **_kwargs: (_ for _ in ()).throw(RuntimeError())) == []
    assert approvals.fetch_approvals("https://relay", "tok", fake_opener([], b"{}")) == []


def test_fetch_approvals_validates_items_and_authorization():
    calls = []
    items = [valid_item(), {**valid_item(), "action_id": "bad"}, {**valid_item(), "nonce": "bad"},
             {**valid_item(), "approved_by": "lowercase"}]
    assert approvals.fetch_approvals("https://relay", "tok", fake_opener(calls, json.dumps(items).encode())) == [valid_item()]
    assert calls[0][1] == "GET" and calls[0][2]["Authorization"] == "Bearer tok"


def test_delete_approval_validates_id_and_sends_delete():
    calls = []
    assert approvals.delete_approval("https://relay/hermes/approvals", "tok", "r2-0123abcd", fake_opener(calls))
    assert calls[0][0] == "https://relay/hermes/approvals/r2-0123abcd" and calls[0][1] == "DELETE"
    assert not approvals.delete_approval("https://relay", "tok", "bad", fake_opener(calls))
    assert len(calls) == 1


def test_interactive_blocks_carry_nonce_and_bound_summary():
    proposals = [{"action_id": "r2-0123abcd", "name": "One", "blast_radius": "low"},
                 {"action_id": "r3-89abcdef", "name": "Two", "blast_radius": "high"}]
    blocks = approvals.interactive_blocks("x" * 5000, proposals, "0123456789abcdef")
    assert len(blocks[0]["text"]["text"]) == 2900
    for proposal, block in zip(proposals, blocks[2::2]):
        assert block["block_id"] == proposal["action_id"]
        assert [element["action_id"] for element in block["elements"]] == ["hermes_approve", "hermes_deny"]
        assert all(element["value"] == f"{proposal['action_id']}|0123456789abcdef" for element in block["elements"])
        assert "confirm" in block["elements"][0]


def test_post_interactive_posts_blocks_and_empty_relay_fails():
    calls, blocks = [], [{"type": "section"}]
    assert post_interactive("https://relay", "hello", blocks, fake_opener(calls))
    assert json.loads(calls[0][3])["blocks"] == blocks and json.loads(calls[0][3])["text"] == "hello"
    assert not post_interactive("", "hello", blocks, fake_opener(calls))


def test_drain_empty_url_does_not_read_keychain(monkeypatch):
    monkeypatch.setattr(k3dm_hermes, "_keychain_secret", lambda *_args: (_ for _ in ()).throw(AssertionError()))
    assert k3dm_hermes._drain_approvals({}, "relay", "") == []


def test_drain_stale_nonce_drops_and_deletes(monkeypatch):
    calls, item = [], valid_item()
    state = {"pending_repairs": {item["action_id"]: {"name": "repair"}}, "incident_nonce": "ffffffffffffffff"}
    monkeypatch.setattr(k3dm_hermes, "_keychain_secret", lambda *_args: "tok")
    monkeypatch.setattr(k3dm_hermes, "fetch_approvals", lambda *_args: [item])
    monkeypatch.setattr(k3dm_hermes, "delete_approval", lambda *_args: calls.append("delete"))
    monkeypatch.setattr(k3dm_hermes.repairs, "approve", lambda *_args: (_ for _ in ()).throw(AssertionError()))
    outcome = k3dm_hermes._drain_approvals(state, "relay", "https://drain")
    assert calls == ["delete"] and outcome[0]["outcome"].startswith("dropped")


def test_drain_unknown_action_drops_and_deletes(monkeypatch):
    calls, item = [], valid_item()
    monkeypatch.setattr(k3dm_hermes, "_keychain_secret", lambda *_args: "tok")
    monkeypatch.setattr(k3dm_hermes, "fetch_approvals", lambda *_args: [item])
    monkeypatch.setattr(k3dm_hermes, "delete_approval", lambda *_args: calls.append("delete"))
    monkeypatch.setattr(k3dm_hermes.repairs, "approve", lambda *_args: (_ for _ in ()).throw(AssertionError()))
    assert k3dm_hermes._drain_approvals({"pending_repairs": {}, "incident_nonce": item["nonce"]}, "relay", "https://drain")[0]["outcome"].startswith("dropped")
    assert calls == ["delete"]


def test_drain_happy_path_approves_deletes_and_posts(monkeypatch):
    calls, item = [], valid_item()
    state = {"pending_repairs": {item["action_id"]: {"name": "repair"}}, "incident_nonce": item["nonce"]}
    monkeypatch.setattr(k3dm_hermes, "_keychain_secret", lambda *_args: "tok")
    monkeypatch.setattr(k3dm_hermes, "fetch_approvals", lambda *_args: [item])
    monkeypatch.setattr(k3dm_hermes, "_run_cycle", lambda *_args: ([], None))
    monkeypatch.setattr(k3dm_hermes.repairs, "approve", lambda action_id, *_args: calls.append(("approve", action_id)) or {"outcome": "executed"})
    monkeypatch.setattr(k3dm_hermes, "delete_approval", lambda *_args: calls.append(("delete", item["action_id"])))
    monkeypatch.setattr(k3dm_hermes, "post_summary", lambda _relay, text: calls.append(("post", text)))
    assert k3dm_hermes._drain_approvals(state, "relay", "https://drain") == [{"action_id": item["action_id"], "outcome": "executed"}]
    assert calls[:2] == [("approve", item["action_id"]), ("delete", item["action_id"])]
    assert "<@UAPPROVER1>" in calls[2][1] and "executed" in calls[2][1]


def test_approval_module_never_executes_and_repairs_is_unchanged():
    source = (ROOT / "scripts/lib/hermes/approvals.py").read_text()
    assert "runner(" not in source and "subprocess" not in source
    if shutil.which("git"):
        assert subprocess.run(["git", "diff", "--quiet", "--", "scripts/lib/hermes/repairs.py"], cwd=ROOT).returncode == 0
