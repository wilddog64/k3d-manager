"""End-to-end regression coverage for the dead Kine compaction alert."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import time
from pathlib import Path
from urllib.request import Request, urlopen

import pytest
import yaml


REPO_ROOT = Path(__file__).resolve().parents[3]
RULES = REPO_ROOT / "scripts/etc/argocd/platform-ops/prometheusrule.yaml"
_notify_spec = importlib.util.spec_from_file_location(
    "alertmanager_notify_behaviour", Path(__file__).with_name("test_alertmanager_notify_behaviour.py"))
notify = importlib.util.module_from_spec(_notify_spec)
assert _notify_spec.loader is not None
_notify_spec.loader.exec_module(notify)
pytestmark = pytest.mark.external("runs pinned Prometheus and Alertmanager images in Docker")


@pytest.fixture
def alertmanager(tmp_path):
    """Reuse the existing pinned Alertmanager fixture and fake Sink."""
    try:
        yield from notify.alertmanager.__wrapped__(tmp_path)
    except PermissionError as exc:
        pytest.skip(f"local socket unavailable for Docker fixture: {exc}")


def run(*args: str, **kwargs: object) -> subprocess.CompletedProcess[str]:
    kwargs.setdefault("check", True)
    return subprocess.run(args, text=True, capture_output=True, **kwargs)


def _rule_test(tmp_path: Path) -> Path:
    source = yaml.safe_load(RULES.read_text())
    rules_path = tmp_path / "rules.yaml"
    rules_path.write_text(yaml.safe_dump({"groups": source["spec"]["groups"]}, sort_keys=False))
    test_path = tmp_path / "kine-test.yaml"
    test_path.write_text(yaml.safe_dump({
        "rule_files": ["/tmp/rules.yaml"],
        "evaluation_interval": "1m",
        "tests": [
            {
                "interval": "1m",
                "input_series": [
                    {"series": "k3dm_hub_kine_last_compaction_timestamp_seconds", "values": "0+0x60"},
                    {"series": "k3dm_hub_kine_state_db_bytes", "values": "2000000000+0x60"},
                    {"series": 'up{job="apiserver"}', "values": "1+0x60"},
                ],
                "alert_rule_test": [
                    {"eval_time": "44m", "alertname": "HubKineCompactionStalled", "exp_alerts": []},
                    {"eval_time": "46m", "alertname": "HubKineCompactionStalled", "exp_alerts": [{
                        "exp_labels": {"group": "hermes", "severity": "warning", "cluster": "hub"},
                        "exp_annotations": _kine_rule()["annotations"],
                    }]},
                ],
            },
            {
                "interval": "1m",
                "input_series": [
                    {"series": "k3dm_hub_kine_last_compaction_timestamp_seconds",
                     "values": "0 0 0 0 0 300 300 300 300 300 600 600 600 600 600 900 900 900 900 900 1200 1200 1200 1200 1200 1500 1500 1500 1500 1500 1800 1800 1800 1800 1800 2100 2100 2100 2100 2100 2400 2400 2400 2400 2400 2700 2700 2700 2700 2700 3000 3000 3000 3000 3000 3300 3300 3300 3300 3300 3600"},
                ],
                "alert_rule_test": [
                    {"eval_time": "60m", "alertname": "HubKineCompactionStalled", "exp_alerts": []},
                ],
            },
        ],
    }))
    return test_path


def _kine_rule() -> dict:
    source = yaml.safe_load(RULES.read_text())
    for group in source["spec"]["groups"]:
        for rule in group.get("rules", []):
            if rule.get("alert") == "HubKineCompactionStalled":
                return rule
    raise AssertionError("HubKineCompactionStalled not found in prometheusrule.yaml")


def test_rule_fires_only_for_stale_compaction_and_api_stays_healthy(tmp_path: Path) -> None:
    test_path = _rule_test(tmp_path)
    try:
        run("docker", "run", "--rm", "-v", f"{test_path}:/tmp/kine-test.yaml:ro",
            "-v", f"{test_path.parent / 'rules.yaml'}:/tmp/rules.yaml:ro",
            "--entrypoint=promtool", "quay.io/prometheus/prometheus:v3.1.0", "test", "rules",
            "/tmp/kine-test.yaml")
    except subprocess.CalledProcessError as exc:
        if "permission denied" in (exc.stderr or "").lower() or "cannot connect" in (exc.stderr or "").lower():
            pytest.skip(f"Docker unavailable: {exc.stderr.strip()}")
        raise


def test_notification_reaches_platform_warning_only(alertmanager) -> None:
    endpoint, sink = alertmanager
    rule = _kine_rule()
    alert = {
        "labels": {"alertname": "HubKineCompactionStalled", **rule["labels"]},
        "annotations": rule["annotations"],
        "startsAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "endsAt": "0001-01-01T00:00:00Z",
        "generatorURL": "http://example.invalid/kine",
    }
    request = Request(f"{endpoint}/api/v2/alerts", data=json.dumps([alert]).encode(),
                      headers={"Content-Type": "application/json"}, method="POST")
    with urlopen(request, timeout=3):
        pass
    notify.wait_for(lambda: len(sink.get("/platform-warning")) >= 1)
    messages = sink.get("/platform-warning")
    assert len(messages) == 1
    assert sink.get("/sms-critical") == []
    assert messages[0]["commonLabels"]["alertname"] == "HubKineCompactionStalled"
    assert "Do NOT restart" in messages[0]["commonAnnotations"]["description"]
