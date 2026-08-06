#!/usr/bin/env bats

DASH="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-cve-autopatch.yaml"

@test "CVE dashboard: ConfigMap and embedded JSON parse" {
  run python3 -c 'import json,sys,yaml; doc=yaml.safe_load(open(sys.argv[1])); json.loads(doc["data"]["cve-autopatch.json"])' "${DASH}"
  [ "$status" -eq 0 ]
}

@test "CVE dashboard: version is bumped for Grafana provisioning refresh" {
  run grep -F '"version": 17' "${DASH}"
  [ "$status" -eq 0 ]
}

@test "CVE dashboard: labels vendor fixes as available rather than installed patches" {
  run grep -F '"patch_status": "available" if finding.get("fixedVersion") else "unavailable"' "${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml"
  [ "$status" -eq 0 ]
  [ "$(grep -c '"patch_status": "available" if finding.get("fixedVersion") else "unavailable"' "${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml")" -eq 2 ]
}

@test "CVE dashboard: excludes obsolete patched metric series during the label transition" {
  run python3 -c '
import json, sys, yaml
dashboard = json.loads(yaml.safe_load(open(sys.argv[1]))["data"]["cve-autopatch.json"])
for panel in dashboard["panels"]:
    if panel["title"] in ["Platform Unique CVEs (by CVE ID)", "Shopping-cart Unique CVEs (by CVE ID)"]:
        assert "patch_status=~\"available|unavailable\"" in panel["targets"][0]["expr"]
' "${DASH}"
  [ "$status" -eq 0 ]
}

@test "CVE dashboard: inventory table uses instant Trivy vulnerability metric" {
  run grep -F 'trivy_vulnerability_inventory' "${DASH}"
  [ "$status" -eq 0 ]
  run grep -F '"instant": true' "${DASH}"
  [ "$status" -eq 0 ]
}

@test "CVE dashboard: unique-CVE tables retain remediation and image detail" {
  for field in vulnerability_id title exported_namespace severity resource_name service package image_tag installed_version fixed_version patch_status Count; do
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

@test "CVE dashboard: both tables deduplicate by CVE ID while preserving distinct finding details" {
  run python3 -c '
import json, sys, yaml
dashboard = json.loads(yaml.safe_load(open(sys.argv[1]))["data"]["cve-autopatch.json"])
panels = {panel["title"]: panel for panel in dashboard["panels"]}
names = ["Platform Unique CVEs (by CVE ID)", "Shopping-cart Unique CVEs (by CVE ID)"]
expected_grouped = ["vulnerability_id", "title", "severity"]
expected_aggregated = ["exported_namespace", "resource_name", "service", "package", "image_tag", "installed_version", "fixed_version", "patch_status"]
for name in names:
    panel = panels[name]
    assert panel["targets"][0]["expr"].startswith("trivy_vulnerability_inventory{")
    group = panel["transformations"][0]
    assert group["id"] == "groupBy"
    fields = group["options"]["fields"]
    assert all(fields[field]["operation"] == "groupby" for field in expected_grouped)
    assert all(fields[field]["aggregations"] == ["uniqueValues"] for field in expected_aggregated)
    assert fields["Value"]["aggregations"] == ["sum"]
    convert = panel["transformations"][1]
    assert convert["id"] == "convertFieldType"
    assert len(convert["options"]["conversions"]) == len(expected_aggregated)
    assert all(item["destinationType"] == "string" and item["joinWith"] == ", " for item in convert["options"]["conversions"])
    organize = panel["transformations"][2]["options"]
    assert organize["renameByName"]["image_tag (uniqueValues)"] == "Image tag"
    assert organize["renameByName"]["installed_version (uniqueValues)"] == "Version"
    assert organize["renameByName"]["fixed_version (uniqueValues)"] == "Fixed version"
    assert panel["fieldConfig"]["overrides"] == [{"matcher": {"id": "byName", "options": "Fix available"}, "properties": [{"id": "displayName", "value": "Fix available"}]}]
    assert organize["renameByName"]["Value (sum)"] == "Count"
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

@test "CVE dashboard: includes durable remediation history table" {
  run python3 -c '
import json, sys, yaml
dashboard = json.loads(yaml.safe_load(open(sys.argv[1]))["data"]["cve-autopatch.json"])
panel = next(panel for panel in dashboard["panels"] if panel["title"] == "Recent CVE Remediations")
assert panel["targets"][0]["expr"] == "cve_remediation_event_info"
assert panel["targets"][0]["instant"] is True
renames = panel["transformations"][0]["options"]["renameByName"]
assert renames == {"cve_ids": "CVE IDs", "service": "Service", "to_image": "Replacement image", "requested_at": "Requested at", "applied_at": "Applied at", "state": "State", "reason": "Reason"}
' "${DASH}"
  [ "$status" -eq 0 ]
}

@test "CVE exporter: exposes bounded remediation lifecycle metrics and event details" {
  EXPORTER="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml"
  for metric in cve_remediation_requested_timestamp_seconds cve_remediation_applied_timestamp_seconds cve_remediation_state cve_remediation_event_info; do
    run grep -F "$metric" "$EXPORTER"
    [ "$status" -eq 0 ]
  done
  run grep -F 'resources: ["configmaps"]' "$EXPORTER"
  [ "$status" -eq 0 ]
}
