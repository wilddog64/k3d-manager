#!/usr/bin/env bats

SCAN_SCRIPT="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/cve-scan.sh"
RBAC_MANIFEST="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/rbac.yaml"

@test "cve scan reads the Hub chart label from argocd-server" {
  run grep -F -- "get deployment argocd-server" "${SCAN_SCRIPT}"
  [ "${status}" -eq 0 ]

  run grep -F -- "metadata.labels.helm\\.sh/chart" "${SCAN_SCRIPT}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'argo-cd-*)' "${SCAN_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "cve scan does not create or patch an infra cluster-secret stage" {
  run grep -F -- '_chart_label "infra"' "${SCAN_SCRIPT}"
  [ "${status}" -ne 0 ]

  run grep -F -- '_patch_stage "infra"' "${SCAN_SCRIPT}"
  [ "${status}" -ne 0 ]

  run grep -F -- 'Hub self-upgrade is external' "${SCAN_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "cve scanner is authorized only to read the Hub deployment" {
  run grep -A2 -F 'resources: ["deployments"]' "${RBAC_MANIFEST}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'verbs: ["get"]'* ]]
}
