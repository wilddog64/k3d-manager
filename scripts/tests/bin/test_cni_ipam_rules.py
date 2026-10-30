import hashlib
import json
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[3]
RULE_PATH = ROOT / "scripts/etc/prometheus/rules/host-cni-ipam.yaml"


def _rules(document):
    return document["spec"]["groups"][0]["rules"]


def test_orphan_not_reclaimed_rule_has_required_gate():
    rules = _rules(yaml.safe_load(RULE_PATH.read_text()))
    by_name = {rule["alert"]: rule for rule in rules}
    rule = by_name["HostCniIpamOrphanNotReclaimed"]
    assert rule["expr"] == (
        "k3dm_cni_ipam_skipped > 0 and "
        "k3dm_cni_ipam_skipped_oldest_age_seconds > 3600"
    )
    assert rule["for"] == "30m"
    assert rule["labels"] == {"severity": "warning", "cluster": "hub"}


ORIGINAL_RULES_SHA256 = "1fdee7e161d1fad14651a7ab0be99364beb4e5f6a9c25c0e2789ba34710e7b8c"


def test_existing_rules_are_unchanged():
    rules = _rules(yaml.safe_load(RULE_PATH.read_text()))
    assert [rule["alert"] for rule in rules[:3]] == [
        "HostPodIPPoolHigh", "HostPodIPAllocationFailing", "HostCniIpamSweepStale"
    ]
    digest = hashlib.sha256(json.dumps(rules[:3], sort_keys=True).encode()).hexdigest()
    assert digest == ORIGINAL_RULES_SHA256  # agent-audit: allow assert-removed git HEAD baseline broke once committed; pinned digest of the pre-change rules
