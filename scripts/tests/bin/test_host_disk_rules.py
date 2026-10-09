import json
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[3]


def test_host_disk_rules_have_expected_alerts_labels_and_thresholds():
    document = yaml.safe_load((ROOT / "scripts/etc/prometheus/rules/host-disk.yaml").read_text())
    rules = document["spec"]["groups"][0]["rules"]
    by_name = {rule["alert"]: rule for rule in rules}
    assert set(by_name) == {"HostDiskSpaceLow", "HostDiskSpaceCritical", "HostDiskMetricsStale"}
    assert all(rule["labels"] == {"severity": rule["labels"]["severity"], "cluster": "hub"}
               for rule in rules)
    assert by_name["HostDiskSpaceLow"]["labels"]["severity"] == "warning"
    assert by_name["HostDiskSpaceCritical"]["labels"]["severity"] == "critical"
    assert "0.80" in by_name["HostDiskSpaceLow"]["expr"]
    assert "0.90" in by_name["HostDiskSpaceCritical"]["expr"]


def test_host_disk_dashboard_configmap_embedded_json_parses():
    document = yaml.safe_load((ROOT / "scripts/etc/argocd/platform-ops/grafana-dashboard-host-disk.yaml").read_text())
    assert document["kind"] == "ConfigMap"
    dashboard = json.loads(document["data"]["host-disk.json"])
    assert dashboard["uid"] == "k3dm-host-disk"
