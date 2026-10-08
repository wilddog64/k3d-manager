"""Unranked (capability) token roles never reach a rank comparison.

docs/bugs/2026-09-28-role-code-assumes-every-token-role-is-ranked.md
"""

import importlib.util
import itertools
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

from webhook import policy  # noqa: E402

_WEBHOOK = ROOT / "bin" / "k3dm-webhook"
_spec = importlib.util.spec_from_file_location(
    "k3dm_webhook_roles", _WEBHOOK, loader=SourceFileLoader("k3dm_webhook_roles", str(_WEBHOOK))
)
wh = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wh)


@pytest.fixture
def cloud_runner(monkeypatch):
    monkeypatch.setitem(policy._ROLE_CAPABILITIES, "cloud-runner", policy.CLOUD_RUNNER_TARGETS)
    return "cloud-runner"


def _make_policy(target):
    return policy._action_policy("/api/v1/make", {"target": target})


def test_capability_token_role_is_returned_unchanged(cloud_runner):
    assert policy._request_role({}, token_role=cloud_runner) == cloud_runner
    assert policy._request_role({"X-K3DM-Role": "admin"}, token_role=cloud_runner) == cloud_runner
    assert policy._effective_make_role({"X-K3DM-Role": "admin"}, {}, token_role=cloud_runner) == cloud_runner


def test_capability_role_is_a_set_not_a_rank(cloud_runner):
    assert policy._policy_allows(cloud_runner, {"name": "make:e2e-remote", "min_role": "operator"})
    assert policy._policy_allows(cloud_runner, {"name": "make:e2e", "min_role": "operator"})
    assert not policy._policy_allows(cloud_runner, _make_policy("test-pytest"))
    assert not policy._policy_allows(cloud_runner, _make_policy("fix-delete-pod"))
    assert not policy._role_allows(cloud_runner, "reader")


def test_unknown_role_without_capability_set_is_refused():
    assert not policy._policy_allows("nonsense", _make_policy("test-pytest"))
    assert not policy._policy_allows("", _make_policy("test-pytest"))


def _legacy_request_role(headers, token_role=None):
    raw = headers.get("X-K3DM-Role")
    if raw is None:
        role = token_role or policy._ROLE_DEFAULT
    else:
        raw = raw.strip().lower()
        role = raw if raw in policy._ROLE_LEVELS else "reader"
    if token_role is not None and policy._ROLE_LEVELS[role] > policy._ROLE_LEVELS[token_role]:
        return token_role
    return role


@pytest.mark.parametrize(
    "token_role,header",
    list(itertools.product([None, "reader", "admin"], [None, "reader", "operator", "admin", "ADMIN ", "bogus", ""])),
)
def test_ranked_roles_are_unchanged(token_role, header):
    headers = {} if header is None else {"X-K3DM-Role": header}
    assert policy._request_role(headers, token_role) == _legacy_request_role(headers, token_role)


def test_thread_command_refusal_names_the_fail_closed_role(monkeypatch):
    sent = []
    monkeypatch.setattr(wh, "_notify_job", lambda _job, text: sent.append(text))
    monkeypatch.setattr(wh, "_audit_remote_action", lambda *a, **k: None)
    wh._handle_thread_command("abc123", "kill", role="nonsense")
    assert sent, "expected a refusal message"
    assert "you have *reader*" in sent[0]
    assert "admin" not in sent[0].split("you have")[1]


def test_empty_token_role_is_not_admin():
    role = policy._request_role({}, token_role="")
    assert role != "admin"
    assert not policy._policy_allows(role, _make_policy("test-pytest"))


@pytest.mark.parametrize(
    ("path", "body", "ceiling", "required"),
    [
        ("/api/v1/cluster", {"action": "up", "provider": "aws"}, "admin", "admin"),
        ("/api/v1/cluster", {"action": "down", "provider": "aws"}, "admin", "admin"),
        ("/api/v1/cluster-resume", {"provider": "aws"}, "admin", "admin"),
        ("/api/v1/cluster-refresh", {"provider": "hostinger"}, "operator", "operator"),
        ("/api/v1/cleanup-stale-sandbox", {"confirm": True}, "admin", "admin"),
        ("/api/v1/argocd-upgrade", {"chart_version": "7.9.1", "stage": "acg", "confirm": False}, "admin", "admin"),
    ],
)
@pytest.mark.parametrize("caller", ["admin", "operator", "reader", "unmapped"])
def test_privileged_relay_routes_cap_before_dispatch(
    monkeypatch, tmp_path, path, body, ceiling, required, caller
):
    monkeypatch.setattr(wh, "JOB_DIR", tmp_path)
    monkeypatch.setattr(wh._Handler, "_auth", lambda self: True)
    monkeypatch.setattr(wh, "_rate_limited", lambda _bucket: False)
    monkeypatch.setattr(policy, "_slack_user_role", lambda _user_id: caller if caller != "unmapped" else "reader")
    audits = []
    monkeypatch.setattr(wh, "_audit_remote_action", lambda *args, **kwargs: audits.append((args, kwargs)))
    started = []
    class Thread:
        def __init__(self, **kwargs):
            started.append(kwargs)

        def start(self):
            return None

    monkeypatch.setattr(wh.threading, "Thread", Thread)

    import json
    request_body = {**body, "slack_user_id": "U1"}
    encoded = json.dumps(request_body).encode()
    result = {}
    fake = type("FakeHandler", (), {
        "path": path,
        "headers": {
            "Content-Length": str(len(encoded)),
            "X-K3DM-Role": ceiling,
            "X-K3DM-Actor": "slack:test:U1",
        },
        "rfile": __import__("io").BytesIO(encoded),
        "wfile": __import__("io").BytesIO(),
        "_auth": lambda self: True,
        "send_response": lambda self, code: result.update(code=code),
        "send_header": lambda self, key, value: None,
        "end_headers": lambda self: None,
        "_json": lambda self, code, response: result.update(code=code, response=response),
    })()

    wh._Handler.do_POST(fake)

    allowed = caller == "admin" or (caller == "operator" and required == "operator")
    if allowed:
        assert result["code"] != 403
    else:
        assert result["code"] == 403
        assert started == []
        assert audits[-1][0][4] is False


def test_direct_token_role_is_unchanged_without_relay_identity():
    assert policy._effective_make_role({}, {}, token_role="admin") == "admin"


def test_cloud_runner_capability_token_is_unchanged_without_relay_identity(cloud_runner):
    assert policy._effective_make_role({}, {}, token_role=cloud_runner) == cloud_runner
