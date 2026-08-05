#!/usr/bin/env bats

DASH="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-cve-autopatch.yaml"

@test "CVE dashboard: ConfigMap and embedded JSON parse" {
  run python3 -c 'import json,sys,yaml; doc=yaml.safe_load(open(sys.argv[1])); json.loads(doc["data"]["cve-autopatch.json"])' "${DASH}"
  [ "$status" -eq 0 ]
}

@test "CVE dashboard: version is bumped for Grafana provisioning refresh" {
  run grep -F '"version": 9' "${DASH}"
  [ "$status" -eq 0 ]
}

@test "CVE dashboard: inventory table uses instant Trivy vulnerability metric" {
  run grep -F 'trivy_vulnerability_inventory' "${DASH}"
  [ "$status" -eq 0 ]
  run grep -F '"instant": true' "${DASH}"
  [ "$status" -eq 0 ]
}

@test "CVE dashboard: inventory exposes workload, image, severity, and CVE columns" {
  for field in resource_name image_repository image_tag image_digest severity vulnerability_id fixed_version patch_status; do
    run grep -F "${field}" "${DASH}"
    [ "$status" -eq 0 ]
  done
}

@test "CVE dashboard: existing alert and remediation panels remain" {
  run grep -F 'Critical CVE Alerts Firing' "${DASH}"
  [ "$status" -eq 0 ]
  run grep -F 'Remediation Jobs (cve-auto-*) Outcomes' "${DASH}"
  [ "$status" -eq 0 ]
}

@test "CVE dashboard: includes a dedicated shopping-cart vulnerability table" {
  run grep -F 'Shopping-cart App Vulnerabilities' "${DASH}"
  [ "$status" -eq 0 ]
  run grep -F 'wilddog64/shopping-cart-.*' "${DASH}"
  [ "$status" -eq 0 ]
}

@test "CVE dashboard: both inventory tables deduplicate identical findings with matching columns" {
  run python3 -c '
import json, sys, yaml
dashboard = json.loads(yaml.safe_load(open(sys.argv[1]))["data"]["cve-autopatch.json"])
panels = {panel["title"]: panel for panel in dashboard["panels"]}
names = ["Platform Image Vulnerabilities (platform services; verify stale reports)", "Shopping-cart App Vulnerabilities"]
expected = {"vulnerability_id": 0, "title": 1, "exported_namespace": 2, "severity": 3, "resource_name": 4, "service": 5, "package": 6, "image_tag": 7, "installed_version": 8, "fixed_version": 9, "patch_status": 10, "Value": 11}
for name in names:
    panel = panels[name]
    assert panel["targets"][0]["expr"].startswith("sum by (vulnerability_id, title, exported_namespace")
    options = panel["transformations"][0]["options"]
    assert options["indexByName"] == expected
    assert options["renameByName"]["exported_namespace"] == "Namespace"
    assert options["excludeByName"]["namespace"] is True
' "${DASH}"
  [ "$status" -eq 0 ]
}

@test "CVE dashboard: labels the general inventory as platform coverage" {
  run grep -F 'Platform Image Vulnerabilities (platform services; verify stale reports)' "${DASH}"
  [ "$status" -eq 0 ]
}

@test "CVE dashboard: namespace panels include hub and shopping-cart clusters" {
  run grep -F 'sum by (cluster, namespace) (trivy_vulnerability_inventory' "${DASH}"
  [ "$status" -eq 0 ]
  run grep -F 'cluster}} / {{namespace}}' "${DASH}"
  [ "$status" -eq 0 ]
}

@test "CVE dashboard: failed remediation count excludes jobs that eventually succeeded" {
  run grep -F 'kube_job_status_succeeded' "${DASH}"
  [ "$status" -eq 0 ]
  run grep -F '== 0)) or vector(0)' "${DASH}"
  [ "$status" -eq 0 ]
}
