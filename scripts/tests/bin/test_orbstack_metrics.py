"""Contract tests for the read-only OrbStack metrics producer."""

import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "bin" / "k3dm-orbstack-metrics"
loader = importlib.machinery.SourceFileLoader("orbstack_metrics", str(SCRIPT))
spec = importlib.util.spec_from_loader("orbstack_metrics", loader)
metrics = importlib.util.module_from_spec(spec)
loader.exec_module(metrics)


def _stub(tmp_path, check_code=0):
    log = tmp_path / "argv.log"
    stub = tmp_path / "orbctl"
    stub.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$ORBSTACK_ARGV_LOG\"\n"
                    "if [ \"$1\" = version ]; then echo 'Version: 2.2.4 (2020400)'; exit 0; fi\n"
                    f"exit {check_code}\n")
    stub.chmod(0o755)
    return log


def _run(monkeypatch, tmp_path, check_code=0, with_stub=True):
    log = _stub(tmp_path, check_code)
    if not with_stub:
        (tmp_path / "orbctl").unlink()
    monkeypatch.setenv("ORBSTACK_ARGV_LOG", str(log))
    monkeypatch.setenv("PATH", f"{tmp_path}:{os.environ['PATH']}" if with_stub else str(tmp_path))
    return subprocess.run([sys.executable, str(SCRIPT), "--dry-run"], capture_output=True, text=True,
                          check=False), log


def test_up_to_date_emits_version_and_gauges(monkeypatch, tmp_path):
    result, _ = _run(monkeypatch, tmp_path)
    assert result.returncode == 0
    assert 'k3dm_orbstack_info{version="2.2.4"} 1' in result.stdout
    assert "k3dm_orbstack_update_available 0" in result.stdout
    assert "k3dm_orbstack_probe_success 1" in result.stdout


def test_exit_three_means_update_available(monkeypatch, tmp_path):
    result, _ = _run(monkeypatch, tmp_path, check_code=3)
    assert "k3dm_orbstack_update_available 1" in result.stdout


def test_failed_check_has_no_update_gauge(monkeypatch, tmp_path):
    result, _ = _run(monkeypatch, tmp_path, check_code=1)
    assert result.returncode == 0
    assert "k3dm_orbstack_probe_success 0" in result.stdout
    assert "k3dm_orbstack_update_available" not in result.stdout


def test_missing_orbctl_is_nonfatal(monkeypatch, tmp_path):
    result, _ = _run(monkeypatch, tmp_path, with_stub=False)
    assert result.returncode == 0
    assert result.stdout == "k3dm_orbstack_probe_success 0\n"


def test_commands_are_read_only_and_check_is_explicit(monkeypatch, tmp_path):
    for code in (0, 3, 1):
        case = tmp_path / str(code)
        case.mkdir()
        _, log = _run(monkeypatch, case, check_code=code)
        assert log.read_text().splitlines() == ["version", "update --check"]


def test_orbstack_rules_have_warning_labels_and_version_join():
    document = yaml.safe_load((ROOT / "scripts/etc/prometheus/rules/host-orbstack.yaml").read_text())
    rules = {rule["alert"]: rule for rule in document["spec"]["groups"][0]["rules"]}
    assert set(rules) == {"OrbStackUpdateAvailable", "OrbStackMetricsStale"}
    assert all(rule["labels"] == {"severity": "warning", "cluster": "hub"} for rule in rules.values())
    update = rules["OrbStackUpdateAvailable"]
    assert "k3dm_orbstack_update_available" in update["expr"]
    assert "k3dm_orbstack_info" in update["expr"]
    assert "orbctl update" in update["annotations"]["description"]


def test_alert_route_and_dashboard_contract():
    template = (ROOT / "scripts/etc/prometheus/alertmanager.yaml.tmpl").read_text()
    assert "OrbStackUpdateAvailable" in template
    document = yaml.safe_load((ROOT / "scripts/etc/argocd/platform-ops/grafana-dashboard-host-disk.yaml").read_text())
    dashboard = json.loads(document["data"]["host-disk.json"])
    assert dashboard["uid"] == "k3dm-host-disk"
    panel = next(panel for panel in dashboard["panels"] if panel["title"] == "OrbStack")
    targets = {target["refId"]: target for target in panel["targets"]}
    assert targets["A"]["expr"] == "k3dm_orbstack_info" and targets["A"]["legendFormat"] == "{{version}}"
    assert targets["B"]["expr"] == "k3dm_orbstack_update_available"
    overrides = {item["matcher"]["options"]: item["properties"][0]["value"][0]["options"]
                 for item in panel["fieldConfig"]["overrides"]}
    assert overrides["B"]["1"]["text"] == "update available"
    assert overrides["A"]["1"]["text"] != "update available"
    assert "mappings" not in panel["fieldConfig"]["defaults"]
    annotation = next(item for item in dashboard["annotations"]["list"] if item["name"] == "OrbStack upgraded")
    assert "offset 1h" in annotation["expr"]
    assert annotation["datasource"]["type"] == "prometheus"
    assert annotation["titleFormat"] == "OrbStack upgraded to {{version}}"
    assert "type" not in annotation and "target" not in annotation


def _promtool(tmp_path, *args):
    import shutil
    if shutil.which("promtool"):
        return subprocess.run(["promtool", *args], capture_output=True, text=True, cwd=tmp_path, check=False)
    if shutil.which("docker"):
        result = subprocess.run(["docker", "run", "--rm", "-v", f"{tmp_path}:/r", "-w", "/r",
                                 "--entrypoint=promtool", "quay.io/prometheus/prometheus:v3.1.0", *args],
                                capture_output=True, text=True, check=False)
        if "cannot connect" not in result.stderr.lower() and "permission denied" not in result.stderr.lower():
            return result
    pytest.skip("promtool unavailable")


import pytest  # noqa: E402


@pytest.mark.external("runs promtool, from PATH or the pinned Prometheus image")
def test_orbstack_rules_parse_and_fire_with_version(tmp_path):
    document = yaml.safe_load((ROOT / "scripts/etc/prometheus/rules/host-orbstack.yaml").read_text())
    (tmp_path / "rules.yaml").write_text(yaml.safe_dump({"groups": document["spec"]["groups"]}))
    update = next(rule for rule in document["spec"]["groups"][0]["rules"]
                  if rule["alert"] == "OrbStackUpdateAvailable")
    check = _promtool(tmp_path, "check", "rules", "rules.yaml")
    assert check.returncode == 0, check.stdout + check.stderr
    labels = 'job="k3dm-orbstack",instance=""'
    (tmp_path / "test.yaml").write_text(yaml.safe_dump({
        "rule_files": ["rules.yaml"], "evaluation_interval": "1m",
        "tests": [{"interval": "1m",
                   "input_series": [
                       {"series": f"k3dm_orbstack_update_available{{{labels}}}", "values": "1x90"},
                       {"series": f'k3dm_orbstack_info{{{labels},version="2.2.5"}}', "values": "1x90"},
                       {"series": f"k3dm_orbstack_probe_success{{{labels}}}", "values": "1x90"},
                       {"series": f"push_time_seconds{{{labels}}}", "values": "0+60x90"}],
                   "alert_rule_test": [
                       {"eval_time": "70m", "alertname": "OrbStackUpdateAvailable",
                        "exp_alerts": [{"exp_labels": {"severity": "warning", "cluster": "hub", "job": "k3dm-orbstack",
                                                       "version": "2.2.5"},
                                        "exp_annotations": {
                                            key: value.replace("{{ $labels.version }}", "2.2.5")
                                            for key, value in update["annotations"].items()}}]},
                       {"eval_time": "70m", "alertname": "OrbStackMetricsStale", "exp_alerts": []}]},
                  {"interval": "1m",
                   "input_series": [
                       {"series": f"k3dm_orbstack_update_available{{{labels}}}", "values": "0x90"},
                       {"series": f'k3dm_orbstack_info{{{labels},version="2.2.5"}}', "values": "1x90"},
                       {"series": f"k3dm_orbstack_probe_success{{{labels}}}", "values": "1x90"},
                       {"series": f"push_time_seconds{{{labels}}}", "values": "0+60x90"}],
                   "alert_rule_test": [
                       {"eval_time": "70m", "alertname": "OrbStackUpdateAvailable", "exp_alerts": []}]}]}))
    result = _promtool(tmp_path, "test", "rules", "test.yaml")
    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.external("runs promtool, from PATH or the pinned Prometheus image")
def test_upgrade_annotation_marks_a_version_change_only(tmp_path):
    dashboard = yaml.safe_load((ROOT / "scripts/etc/argocd/platform-ops/grafana-dashboard-host-disk.yaml").read_text())
    board = json.loads(next(iter(dashboard["data"].values())))
    expr = next(item for item in board["annotations"]["list"] if item["name"] == "OrbStack upgraded")["expr"]
    (tmp_path / "rules.yaml").write_text(yaml.safe_dump({"groups": [{"name": "annotation", "rules": [
        {"alert": "OrbStackUpgradedMark", "expr": expr}]}]}))
    labels = 'job="k3dm-orbstack",instance=""'

    def case(series, eval_time, versions):
        return {"interval": "1m", "input_series": [
            {"series": f'k3dm_orbstack_info{{{labels},version="{version}"}}', "values": values}
            for version, values in series],
            "alert_rule_test": [{"eval_time": eval_time, "alertname": "OrbStackUpgradedMark", "exp_alerts": [
                {"exp_labels": {"job": "k3dm-orbstack", "version": version}} for version in versions]}]}

    (tmp_path / "test.yaml").write_text(yaml.safe_dump({"rule_files": ["rules.yaml"], "evaluation_interval": "1m",
        "tests": [
            case([("2.2.5", "_x119 1x60")], "130m", []),
            case([("2.2.4", "1x119"), ("2.2.5", "_x119 1x60")], "130m", ["2.2.5"]),
            case([("2.2.5", "1x60 _x139 1x30")], "210m", []),
        ]}))
    result = _promtool(tmp_path, "test", "rules", "test.yaml")
    assert result.returncode == 0, result.stdout + result.stderr
