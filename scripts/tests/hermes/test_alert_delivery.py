import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))

from hermes.sensors import alert_delivery


def run_payload(payload, code=0):
    return lambda _command, _env: (code, json.dumps(payload))


def cluster(**overrides):
    value = {
        "context": "k3d-k3d-cluster",
        "config_secret": "alertmanager-smtp-secret",
        "config_secret_missing": False,
        "root_receiver_is_null": False,
        "child_routes": 4,
    }
    value.update(overrides)
    return value


def test_healthy_cluster_names_count():
    result = alert_delivery(run_payload({"available": True, "clusters": [cluster()]}), {})
    assert result["status"] == "healthy"
    assert "1 Alertmanager" in result["evidence"]


def test_missing_config_secret_degrades_on_second_cycle():
    payload = {"available": True, "clusters": [cluster(config_secret_missing=True)]}
    state = {}
    alert_delivery(run_payload(payload), state)
    result = alert_delivery(run_payload(payload), state)
    assert result["status"] == "degraded"
    assert "alertmanager-smtp-secret" in result["evidence"]
    assert "k3d-k3d-cluster" in result["evidence"]


def test_first_blackout_cycle_is_debounced():
    state = {}
    result = alert_delivery(run_payload({"available": True, "clusters": [cluster(config_secret_missing=True)]}), state)
    assert result["status"] == "healthy"
    assert state["debounce"]["alert_delivery"] == 1


def test_null_root_with_escape_route_is_healthy():
    result = alert_delivery(run_payload({"available": True, "clusters": [cluster(root_receiver_is_null=True, child_routes=4)]}), {})
    assert result["status"] == "healthy"


def test_null_root_without_children_degrades_on_second_cycle():
    payload = {"available": True, "clusters": [cluster(root_receiver_is_null=True, child_routes=0)]}
    state = {}
    alert_delivery(run_payload(payload), state)
    result = alert_delivery(run_payload(payload), state)
    assert result["status"] == "degraded"


def test_unavailable_probe_is_unknown():
    result = alert_delivery(run_payload({"available": False, "clusters": []}, code=1), {})
    assert result["status"] == "unknown"


def test_invalid_cluster_entries_are_unknown():
    for clusters in (["not-a-dict"], [{"root_receiver_is_null": True}]):
        result = alert_delivery(run_payload({"available": True, "clusters": clusters}), {})
        assert result["status"] == "unknown"


def test_healthy_cycle_resets_blackout_debounce():
    state = {}
    bad = {"available": True, "clusters": [cluster(config_secret_missing=True)]}
    alert_delivery(run_payload(bad), state)
    good = alert_delivery(run_payload({"available": True, "clusters": [cluster()]}), state)
    assert good["status"] == "healthy"
    assert state["debounce"]["alert_delivery"] == 0
