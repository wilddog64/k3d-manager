import ast
import json
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[3]
EXPORTER = ROOT / "scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml"
READER_RBAC = ROOT / "scripts/etc/argocd/hostinger-cve-inventory-reader/rbac.yaml"
DASHBOARD = ROOT / "scripts/etc/argocd/platform-ops/grafana-dashboard-cve-autopatch.yaml"
RULE = ROOT / "scripts/etc/argocd/platform-ops/prometheusrule.yaml"
ACG_VALUES = ROOT / "scripts/etc/helm/observability/trivy-operator-acg-values.yaml"


def exporter_source():
    docs = list(yaml.safe_load_all(EXPORTER.read_text()))
    config = next(doc for doc in docs if doc and doc.get("kind") == "ConfigMap"
                  and doc["metadata"]["name"] == "vulnerability-inventory-exporter")
    return config["data"]["exporter.py"]


def coverage_function():
    tree = ast.parse(exporter_source())
    names = {"image_repository", "report_resource_name", "image_scan_coverage"}
    nodes = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name in names]
    namespace = {}
    exec(compile(ast.Module(body=nodes, type_ignores=[]), "exporter", "exec"), namespace)
    return namespace["image_scan_coverage"]


def pod(image, namespace="shopping-cart-apps", owner="catalog-7d54c9"):
    return {
        "metadata": {"namespace": namespace, "name": "catalog-pod", "ownerReferences": [{"name": owner}]},
        "status": {"phase": "Running"},
        "spec": {"containers": [{"image": image}]},
    }


def report(repository, namespace="shopping-cart-apps", owner="catalog-7d54c9", vulnerabilities=None):
    return {
        "metadata": {"namespace": namespace, "name": "report", "ownerReferences": [{"name": owner}]},
        "report": {"artifact": {"repository": repository}, "vulnerabilities": vulnerabilities or []},
    }


def test_report_with_zero_findings_is_scanned():
    coverage = coverage_function()([pod("ghcr.io/wilddog64/shopping-cart-product-catalog:v2")],
                                   [report("wilddog64/shopping-cart-product-catalog")])
    labels = next(iter(coverage.values()))
    assert labels["scanned"] == "true"
    assert labels["image_repository"] == "wilddog64/shopping-cart-product-catalog"
    assert labels["workload"] == "catalog-7d54c9"


def test_missing_report_is_unscanned_and_non_wilddog_images_are_ignored():
    coverage = coverage_function()([
        pod("registry.example.io/wilddog64/shopping-cart-payment:latest", "shopping-cart-payment"),
        pod("docker.io/library/nginx:1.27"),
        {**pod("ghcr.io/wilddog64/stopped:v1"), "status": {"phase": "Succeeded"}},
    ], [])
    assert len(coverage) == 1
    labels = next(iter(coverage.values()))
    assert labels == {
        "cluster": "ubuntu-hostinger",
        "namespace": "shopping-cart-payment",
        "workload": "catalog-7d54c9",
        "image_repository": "wilddog64/shopping-cart-payment",
        "scanned": "false",
    }


def test_reader_role_adds_only_read_only_pod_access():
    docs = list(yaml.safe_load_all(READER_RBAC.read_text()))
    role = next(doc for doc in docs if doc and doc.get("kind") == "ClusterRole")
    rules = role["rules"]
    assert rules[0] == {
        "apiGroups": ["aquasecurity.github.io"],
        "resources": ["vulnerabilityreports"],
        "verbs": ["get", "list", "watch"],
    }
    assert rules[1] == {"apiGroups": [""], "resources": ["pods"], "verbs": ["get", "list"]}
    assert len(rules) == 2


def test_dashboard_has_adjacent_no_report_table_and_warning_alert():
    document = yaml.safe_load(DASHBOARD.read_text())
    dashboard = json.loads(document["data"]["cve-autopatch.json"])
    critical = next(panel for panel in dashboard["panels"] if panel["id"] == 11)
    no_report = next(panel for panel in dashboard["panels"] if panel["title"] == "Our images with no Trivy report")
    assert no_report["targets"][0]["expr"] == 'trivy_image_scan_coverage{scanned="false"}'
    assert "critical table cannot vouch" in no_report["description"]
    assert "Check the no-report table first: an unscanned image also shows nothing here." in critical["description"]
    assert critical["gridPos"]["x"] + critical["gridPos"]["w"] == no_report["gridPos"]["x"]
    organize = next(t for t in no_report["transformations"] if t["id"] == "organize")["options"]
    assert organize["renameByName"]["exported_namespace"] == "Namespace"
    assert organize["excludeByName"]["namespace"] is True

    rule = yaml.safe_load(RULE.read_text())
    rules = [r for group in rule["spec"]["groups"] for r in group["rules"]]
    alert = next(item for item in rules if item["alert"] == "TrivyImageNotScanned")
    assert alert["expr"] == 'trivy_image_scan_coverage{scanned="false"} == 1'
    assert alert["for"] == "6h"
    assert alert["labels"]["severity"] == "warning"
    assert "$labels.exported_namespace" in alert["annotations"]["summary"]
    assert "$labels.namespace" not in alert["annotations"]["summary"] + alert["annotations"]["description"]
    assert "image_repository" in alert["annotations"]["summary"]


def test_acg_scan_slot_does_not_retain_finished_jobs():
    values = yaml.safe_load(ACG_VALUES.read_text())
    operator = values["operator"]
    assert operator["scanJobsConcurrentLimit"] == 1
    assert "scanJobTTL" not in operator
    assert not ("scanJobTTL" in operator and operator["scanJobsConcurrentLimit"] < 3)


def test_existing_finding_and_report_timestamp_series_remain_unchanged():
    source = exporter_source()
    assert 'lines.append("trivy_vulnerability_inventory{" + body + "} 1")' in source
    assert 'lines.append("trivy_vulnerability_report_created_timestamp_seconds{" + body + "} " + num(created_seconds))' in source

