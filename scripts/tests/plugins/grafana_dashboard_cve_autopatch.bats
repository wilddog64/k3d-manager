#!/usr/bin/env bats

DASH="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-cve-autopatch.yaml"

@test "CVE dashboard: ConfigMap and embedded JSON parse" {
  run python3 -c 'import json,sys,yaml; doc=yaml.safe_load(open(sys.argv[1])); json.loads(doc["data"]["cve-autopatch.json"])' "${DASH}"
  [ "$status" -eq 0 ]
}

@test "CVE dashboard: version is bumped for Grafana provisioning refresh" {
  run grep -F '"version": 10' "${DASH}"
  [ "$status" -eq 0 ]
}

@test "CVE dashboard: inventory table uses instant Trivy vulnerability metric" {
  run grep -F 'trivy_vulnerability_inventory' "${DASH}"
  [ "$status" -eq 0 ]
  run grep -F '"instant": true' "${DASH}"
  [ "$status" -eq 0 ]
}

@test "CVE dashboard: unique-CVE tables expose identity, severity, and affected-finding count" {
  for field in vulnerability_id title severity 'Affected findings'; do
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

@test "CVE dashboard: includes a dedicated shopping-cart unique-CVE table" {
  run grep -F 'Shopping-cart Unique CVEs (by CVE ID)' "${DASH}"
  [ "$status" -eq 0 ]
  run grep -F 'wilddog64/shopping-cart-.*' "${DASH}"
  [ "$status" -eq 0 ]
}

@test "CVE dashboard: both tables deduplicate findings by CVE ID with matching columns" {
  run python3 -c '
import json, sys, yaml
dashboard = json.loads(yaml.safe_load(open(sys.argv[1]))["data"]["cve-autopatch.json"])
panels = {panel["title"]: panel for panel in dashboard["panels"]}
names = ["Platform Unique CVEs (by CVE ID)", "Shopping-cart Unique CVEs (by CVE ID)"]
expected = {"vulnerability_id": 0, "title": 1, "severity": 2, "Value": 3}
for name in names:
    panel = panels[name]
    assert panel["targets"][0]["expr"].startswith("sum by (vulnerability_id, title, severity)")
    options = panel["transformations"][0]["options"]
    assert options["indexByName"] == expected
    assert options["renameByName"]["Value"] == "Affected findings"
    assert options["excludeByName"]["namespace"] is True
' "${DASH}"
  [ "$status" -eq 0 ]
}

@test "CVE dashboard: labels the general inventory as platform coverage" {
  run grep -F 'Platform Unique CVEs (by CVE ID)' "${DASH}"
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
