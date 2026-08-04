#!/usr/bin/env bats

DASH="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-cve-autopatch.yaml"

@test "CVE dashboard: ConfigMap and embedded JSON parse" {
  run python3 -c 'import json,sys,yaml; doc=yaml.safe_load(open(sys.argv[1])); json.loads(doc["data"]["cve-autopatch.json"])' "${DASH}"
  [ "$status" -eq 0 ]
}

@test "CVE dashboard: inventory table uses instant Trivy vulnerability metric" {
  run grep -F 'trivy_vulnerability_inventory' "${DASH}"
  [ "$status" -eq 0 ]
  run grep -F '"instant": true' "${DASH}"
  [ "$status" -eq 0 ]
}

@test "CVE dashboard: inventory exposes workload, image, severity, and CVE columns" {
  for field in resource_name image_repository image_tag image_digest severity vulnerability_id patch_status; do
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
