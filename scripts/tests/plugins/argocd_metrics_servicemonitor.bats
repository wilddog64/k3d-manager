#!/usr/bin/env bats

VALUES="${BATS_TEST_DIRNAME}/../../etc/argocd/values.yaml.tmpl"
PLUGIN="${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
DASH="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-argocd.yaml"

@test "metrics: serviceMonitor enabled for all four components" {
  run grep -cF -- 'serviceMonitor:' "${VALUES}"
  [ "${status}" -eq 0 ]
  [ "${output}" -ge 4 ]
}

@test "metrics: prometheus-operator discovery label present per component" {
  run grep -cF -- 'release: kube-prometheus-stack' "${VALUES}"
  [ "${status}" -eq 0 ]
  [ "${output}" -ge 4 ]
}

@test "metrics: dashboard ConfigMap carries grafana sidecar label" {
  run grep -F -- 'grafana_dashboard: "1"' "${DASH}"
  [ "${status}" -eq 0 ]
}

@test "metrics: dashboard targets monitoring namespace" {
  run grep -F -- 'namespace: monitoring' "${DASH}"
  [ "${status}" -eq 0 ]
}

@test "metrics: dashboard applied from argocd.sh platform-ops deploy" {
  run grep -F -- 'grafana-dashboard-argocd.yaml' "${PLUGIN}"
  [ "${status}" -eq 0 ]
}

@test "metrics: dashboard includes image updater deployment readiness panels" {
  run grep -F -- 'kube_deployment_status_replicas_available{namespace=\"cicd\",deployment=\"argocd-image-updater\"}' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'kube_deployment_spec_replicas{namespace=\"cicd\",deployment=\"argocd-image-updater\"}' "${DASH}"
  [ "${status}" -eq 0 ]
}

@test "metrics: dashboard focuses sync activity on watched image-updater apps" {
  run grep -F -- 'argocd_app_sync_total{name=~\"shopping-cart-(basket|order|product-catalog)\"}' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'argocd_app_info{name=~\"shopping-cart-(basket|order|product-catalog)\"}' "${DASH}"
  [ "${status}" -eq 0 ]
}

@test "metrics: dashboard includes a loki log panel for image-updater processing results" {
  run grep -F -- '"uid": "loki"' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'type": "loki"' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Image Updater Processing Results' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"uid": "prometheus"' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"templating": { "list": [] }' "${DASH}"
  [ "${status}" -eq 0 ]
}
