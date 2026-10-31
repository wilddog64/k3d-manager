"""Promtool regression for the persistent fixable critical CVE alert."""
import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

pytestmark = pytest.mark.external("runs promtool or pinned Prometheus image")

RULES = Path(__file__).resolve().parents[3] / "scripts/etc/argocd/platform-ops/prometheusrule.yaml"


def test_fixable_critical_survives_digest_change(tmp_path):
    promtool = shutil.which("promtool")
    source = yaml.safe_load(RULES.read_text())
    rule = next(r for g in source["spec"]["groups"] for r in g["rules"]
                if r.get("alert") == "CriticalCVEFixAvailableNotRemediated")
    (tmp_path / "rules.yml").write_text(yaml.safe_dump({"groups": [{"name": "cve", "rules": [rule]}]}))
    labels = 'severity="CRITICAL",patch_status="available",image_repository="wilddog64/app",vulnerability_id="CVE-1"'
    test = {"rule_files": ["rules.yml"], "evaluation_interval": "1h", "tests": [{
        "interval": "1h", "input_series": [
            {"series": f'trivy_vulnerability_inventory{{{labels},digest="old"}}', "values": "1+0x23 stale _x25"},
            {"series": f'trivy_vulnerability_inventory{{{labels},digest="new"}}', "values": "_x24 1+0x24"},
            {"series": 'trivy_vulnerability_inventory{severity="CRITICAL",patch_status="unavailable",image_repository="wilddog64/app",vulnerability_id="CVE-2"}', "values": "1+0x48"},
            {"series": 'trivy_vulnerability_inventory{severity="CRITICAL",patch_status="available",image_repository="other/app",vulnerability_id="CVE-3"}', "values": "1+0x48"},
        ], "alert_rule_test": [
            {"eval_time": "47h", "alertname": rule["alert"], "exp_alerts": []},
            {"eval_time": "48h", "alertname": rule["alert"], "exp_alerts": [{
                "exp_labels": {"group": "trivy-operator", "severity": "warning", "image_repository": "wilddog64/app", "vulnerability_id": "CVE-1"},
                "exp_annotations": {"summary": rule["annotations"]["summary"], "description": "CVE-1 in wilddog64/app remains open for two days; see docs/guides/grafana-dashboards/cve-autopatch.md."},
            }]},
        ]}]}
    (tmp_path / "test.yml").write_text(yaml.safe_dump(test))
    if promtool:
        subprocess.run([promtool, "test", "rules", str(tmp_path / "test.yml")], check=True)
    else:
        docker = shutil.which("docker")
        if not docker:
            pytest.skip("promtool and Docker unavailable")
        result = subprocess.run([docker, "run", "--rm", "-v", f"{tmp_path}:/work:ro",
                                 "-w", "/work", "--entrypoint=promtool",
                                 "quay.io/prometheus/prometheus:v3.1.0", "test", "rules", "test.yml"],
                                text=True, capture_output=True)
        if result.returncode and ("cannot connect" in result.stderr.lower() or
                                  "permission denied" in result.stderr.lower()):
            pytest.skip(f"Docker unavailable: {result.stderr.strip()}")
        assert result.returncode == 0, result.stdout + result.stderr
