from copy import deepcopy
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
POLICY_PATH = ROOT / "docs" / "howto" / "tailscale" / "policy.hujson"
assert POLICY_PATH.is_file(), f"missing shipped policy: {POLICY_PATH}"


EXPECTED_GRANTS = [
    {"src": ["group:operator"], "dst": ["tag:k3dm-mac"], "ip": ["tcp:22", "tcp:5900"]},
    {"src": ["tag:k3dm-mac"], "dst": ["tag:k3dm-mac"], "ip": ["tcp:22"]},
]
EXPECTED_TESTS = [
    {
        "src": "operator@example.com",
        "proto": "tcp",
        "accept": ["tag:k3dm-mac:22", "tag:k3dm-mac:5900"],
        "deny": ["tag:k3dm-mac:443", "tag:k3dm-mac:8080"],
    },
    {
        "src": "operator@example.com",
        "proto": "udp",
        "deny": ["tag:k3dm-mac:22", "tag:k3dm-mac:5900"],
    },
    {
        "src": "tag:k3dm-mac",
        "proto": "tcp",
        "accept": ["tag:k3dm-mac:22"],
        "deny": ["tag:k3dm-mac:5900", "tag:k3dm-mac:443"],
    },
]


def load() -> dict:
    return json.loads(POLICY_PATH.read_text(encoding="utf-8"))


def _strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, item in value.items():
            yield from _strings(key)
            yield from _strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from _strings(item)


def _order_insensitive(items):
    if not isinstance(items, list):
        return None
    return sorted(json.dumps(item, sort_keys=True) for item in items)


def validate(policy: dict) -> list[str]:
    violations = []
    if not isinstance(policy, dict):
        return ["policy must be an object"]

    if set(policy) != {"groups", "tagOwners", "grants", "tests"}:
        violations.append("top-level keys differ")
    if policy.get("groups") != {"group:operator": ["operator@example.com"]}:
        violations.append("groups differ")
    if policy.get("tagOwners") != {"tag:k3dm-mac": ["group:operator"]}:
        violations.append("tagOwners differ")

    grants = policy.get("grants")
    if not isinstance(grants, list) or any(
        not isinstance(grant, dict) or set(grant) != {"src", "dst", "ip"}
        for grant in (grants if isinstance(grants, list) else [])
    ):
        violations.append("grant keys differ")
    if _order_insensitive(grants) != _order_insensitive(EXPECTED_GRANTS):
        violations.append("grants differ")

    tests = policy.get("tests")
    if not isinstance(tests, list) or any(
        not isinstance(entry, dict) or set(entry) not in (
            {"src", "proto", "accept", "deny"}, {"src", "proto", "deny"}
        )
        for entry in (tests if isinstance(tests, list) else [])
    ):
        violations.append("test entry keys differ")
    if _order_insensitive(tests) != _order_insensitive(EXPECTED_TESTS):
        violations.append("tests differ")

    for value in _strings(policy):
        if any(token in value for token in ("*", "autogroup:", "/", "tskey-", ".ts.net")):
            violations.append(f"forbidden string: {value}")
        if re.search(r"100\.\d+\.\d+\.\d+", value):
            violations.append(f"tailnet address: {value}")
        if "@" in value and value != "operator@example.com":
            violations.append(f"non-placeholder login: {value}")
    return violations


def test_shipped_policy_is_valid():
    assert validate(load()) == []


def _changed(change):
    policy = deepcopy(load())
    change(policy)
    assert validate(policy)


def test_rejects_wildcard_destination():
    _changed(lambda p: p["grants"][0].update(dst=["*"]))


def test_rejects_wildcard_port():
    _changed(lambda p: p["grants"][0].update(ip=["tcp:*"]))


def test_rejects_extra_operator_port():
    _changed(lambda p: p["grants"][0]["ip"].append("tcp:443"))


def test_rejects_mac_screen_sharing():
    _changed(lambda p: p["grants"][1]["ip"].append("tcp:5900"))


def test_rejects_third_grant():
    _changed(lambda p: p["grants"].append({"src": ["tag:k3dm-mac"], "dst": ["group:operator"], "ip": ["tcp:22"]}))


def test_rejects_mixed_operator_source():
    _changed(lambda p: p["grants"][0].update(src=["group:operator", "tag:k3dm-mac"]))


def test_rejects_app_grant_key():
    _changed(lambda p: p["grants"][0].update(app={}))


def test_rejects_cidr_source():
    policy = deepcopy(load())
    policy["grants"][0].update(src=["100.64.0.0/10"])
    violations = validate(policy)
    assert any("forbidden string" in violation for violation in violations)
    assert any("tailnet address" in violation for violation in violations)


def test_rejects_autogroup_tag_owner():
    policy = deepcopy(load())
    policy["tagOwners"].update({"tag:k3dm-mac": ["group:operator", "autogroup:member"]})
    assert any("forbidden string" in violation for violation in validate(policy))


def test_rejects_second_operator_member():
    _changed(lambda p: p["groups"].update({"group:operator": ["operator@example.com", "other@example.com"]}))


def test_rejects_real_login():
    policy = deepcopy(load())
    policy["groups"].update({"group:operator": ["someone@gmail.com"]})
    assert any("non-placeholder login" in violation for violation in validate(policy))


def test_rejects_ssh_key():
    _changed(lambda p: p.update(ssh={}))


def test_rejects_acls_key():
    _changed(lambda p: p.update(acls=[]))


def test_rejects_auto_approvers_key():
    _changed(lambda p: p.update(autoApprovers={}))


def test_rejects_node_attrs_key():
    _changed(lambda p: p.update(nodeAttrs=[]))


def test_rejects_missing_deny():
    _changed(lambda p: p["tests"][0].pop("deny"))


def test_rejects_missing_proto():
    _changed(lambda p: p["tests"][0].pop("proto"))
