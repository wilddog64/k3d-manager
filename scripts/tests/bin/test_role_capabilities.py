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
    monkeypatch.setitem(policy._ROLE_CAPABILITIES, "cloud-runner", frozenset({"make:e2e-remote"}))
    return "cloud-runner"


def _make_policy(target):
    return policy._action_policy("/api/v1/make", {"target": target})


def test_capability_token_role_is_returned_unchanged(cloud_runner):
    assert policy._request_role({}, token_role=cloud_runner) == cloud_runner
    assert policy._request_role({"X-K3DM-Role": "admin"}, token_role=cloud_runner) == cloud_runner
    assert policy._effective_make_role({"X-K3DM-Role": "admin"}, {}, token_role=cloud_runner) == cloud_runner


def test_capability_role_is_a_set_not_a_rank(cloud_runner):
    assert policy._policy_allows(cloud_runner, {"name": "make:e2e-remote", "min_role": "operator"})
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
