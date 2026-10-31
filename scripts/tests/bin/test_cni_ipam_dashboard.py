import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

import yaml


ROOT = Path(os.environ.get("K3DM_TEST_ROOT", Path(__file__).resolve().parents[3]))
DASHBOARD_PATH = ROOT / "scripts/etc/argocd/platform-ops/grafana-dashboard-host-cni-ipam.yaml"
GUIDE_PATH = ROOT / "docs/guides/grafana-dashboards.md"


def dashboard():
    document = yaml.safe_load(DASHBOARD_PATH.read_text())
    return document, json.loads(document["data"]["host-cni-ipam.json"])


def test_configmap_and_dashboard_identity():
    document, dashboard_json = dashboard()
    assert document["kind"] == "ConfigMap"
    assert document["metadata"]["namespace"] == "monitoring"
    assert document["metadata"]["labels"] == {
        "grafana_dashboard": "1",
        "release": "kube-prometheus-stack",
    }
    assert dashboard_json["uid"] == "k3dm-host-cni-ipam"
    assert dashboard_json["title"] == "k3dm Host Pod IP Pool"


def test_dashboard_has_required_panels_with_unique_ids():
    _, dashboard_json = dashboard()
    panels = dashboard_json["panels"]
    assert [panel["title"] for panel in panels] == [
        "Pool used %",
        "Reservations",
        "Allocation errors (1h)",
        "Probe status",
        "Pool used % over time",
        "Stale reservations removed per sweep",
        "Since last sweep",
        "Last push age",
        "In use",
        "Starting (grace period)",
        "Held without a sandbox",
        "Oldest held without a sandbox",
        "Reservations by outcome",
    ]
    assert len({panel["id"] for panel in panels}) == len(panels)


def test_dashboard_queries_only_emitted_series():
    _, dashboard_json = dashboard()
    allowed_series = {
        "k3dm_cni_ipam_reservations",
        "k3dm_cni_ipam_range_size",
        "k3dm_cni_ipam_alloc_errors_1h",
        "k3dm_cni_ipam_probe_success",
        "k3dm_cni_ipam_stale_last_run",
        "k3dm_cni_ipam_sweep_last_run_timestamp_seconds",
        "k3dm_cni_ipam_kept",
        "k3dm_cni_ipam_young",
        "k3dm_cni_ipam_skipped",
        "k3dm_cni_ipam_skipped_oldest_age_seconds",
        "push_time_seconds",
    }
    for panel in dashboard_json["panels"]:
        for target in panel["targets"]:
            expr = target["expr"]
            series = set(re.findall(r"\b(?:k3dm_cni_ipam_[a-zA-Z0-9_]+|push_time_seconds)\b", expr))
            assert series <= allowed_series
            if "push_time_seconds" in expr:
                assert 'job="k3dm-cni-ipam"' in expr


def test_pool_used_panels_warn_at_eighty_percent():
    _, dashboard_json = dashboard()
    panels = [panel for panel in dashboard_json["panels"] if "Pool used %" in panel["title"]]
    assert panels
    for panel in panels:
        steps = panel["fieldConfig"]["defaults"]["thresholds"]["steps"]
        assert {step["value"] for step in steps} >= {80}


def test_guide_names_dashboard_in_inventory_and_triage():
    guide = GUIDE_PATH.read_text()
    assert "| k3dm Host Pod IP Pool | `k3dm-host-cni-ipam` |" in guide
    triage = (GUIDE_PATH.parent / "grafana-dashboards" / "shared-operations.md").read_text()
    assert "**k3dm Host Pod IP Pool** shows `No data`" in triage  # agent-audit: allow assert-removed same assertion, now on the split sub-page


def test_host_disk_dashboard_keeps_its_panels_and_adds_only_orbstack():
    path = ROOT / "scripts/etc/argocd/platform-ops/grafana-dashboard-host-disk.yaml"
    expected = subprocess.run(
        ["git", "show", "5a96bfb7:scripts/etc/argocd/platform-ops/grafana-dashboard-host-disk.yaml"],
        cwd=Path(__file__).resolve().parents[3],
        check=True,
        capture_output=True,
    ).stdout

    def dashboard(text):
        return json.loads(yaml.safe_load(text)["data"]["host-disk.json"])

    # agent-audit: allow assert-removed byte pin replaced by panel-level equality so the OrbStack panel can be added
    before, after = dashboard(expected), dashboard(path.read_bytes())
    added_panels = after["panels"][len(before["panels"]):]
    host_tiles = [panel for panel in after["panels"] if panel["title"] in ("Used %", "Free", "Probe status")]
    assert [panel.pop("options") for panel in host_tiles] == [{"orientation": "vertical"}] * 3
    assert after["panels"][:len(before["panels"])] == before["panels"]
    assert [panel["title"] for panel in added_panels] == ["OrbStack"]
    assert [item["name"] for item in after["annotations"]["list"]] == ["OrbStack upgraded"]
    # agent-audit: allow assert-removed refresh moved out of the key-equality pin to its own 5m assertion (v1.43.7 dashboard refresh)
    assert after["refresh"] == "5m"
    assert {key: value for key, value in after.items() if key not in ("panels", "annotations", "refresh")} == \
        {key: value for key, value in before.items() if key not in ("panels", "annotations", "refresh")}


def test_n1_guide_does_not_reference_missing_dashboard():
    guide = GUIDE_PATH.read_text()
    dashboard_files = list((ROOT / "scripts/etc/argocd/platform-ops").glob("grafana-dashboard-*.yaml"))
    assert "Pod IP pool panels" not in guide or any(
        "k3dm_cni_ipam_reservations" in path.read_text() for path in dashboard_files
    )


def test_every_stat_panel_sets_its_own_thresholds_or_mappings():
    _, dashboard_json = dashboard()
    for panel in dashboard_json["panels"]:
        if panel["type"] != "stat":
            continue
        defaults = panel["fieldConfig"]["defaults"]
        assert "thresholds" in defaults or "mappings" in defaults, panel["title"]


ORIGINAL_PANELS_SHA256 = "0362cb7bb68e18c468968dc5692101620ca7bf4078fca6cb52d1bff38a6ba0e9"


def test_original_panels_are_unchanged():
    _, current = dashboard()
    digest = hashlib.sha256(json.dumps(current["panels"][:8], sort_keys=True).encode()).hexdigest()
    assert digest == ORIGINAL_PANELS_SHA256  # agent-audit: allow assert-removed git HEAD baseline broke once committed; pinned digest of the pre-change panels


def test_guide_documents_outcome_row_and_alert():
    subdoc = (GUIDE_PATH.parent / "grafana-dashboards" / "k3dm-host-cni-ipam.md").read_text()
    for token in ("k3dm_cni_ipam_skipped", "k3dm_cni_ipam_skipped_oldest_age_seconds",
                  "k3dm_cni_ipam_young", "needs host refresh", "HostCniIpamOrphanNotReclaimed"):
        assert token in subdoc, token
    alerting = (ROOT / "docs/guides/alerting.md").read_text()
    assert "| `HostCniIpamOrphanNotReclaimed` fires |" in alerting
