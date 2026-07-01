#!/usr/bin/env bats

SETTINGS="${BATS_TEST_DIRNAME}/../../etc/helm/observability/trivy-operator-values.yaml"
HUB_APPSET="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/observability.yaml"
ACG_APPSET="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/observability-acg.yaml"
DASH="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-argocd.yaml"
RULE="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/prometheusrule.yaml"
ROUTE="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/alertmanager-config.yaml"

@test "trivy observability: charts pin trivy-operator 0.31.2 in both application sets" {
  run grep -F -- 'targetRevision: 0.31.2' "${HUB_APPSET}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'targetRevision: 0.31.2' "${ACG_APPSET}"
  [ "${status}" -eq 0 ]
}

@test "trivy observability: chart values enable serviceMonitor scraping" {
  run grep -F -- 'serviceMonitor:' "${SETTINGS}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'enabled: true' "${SETTINGS}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'release: kube-prometheus-stack' "${SETTINGS}"
  [ "${status}" -eq 0 ]
}

@test "trivy observability: dashboard exposes log and metric panels for trivy-system" {
  run grep -F -- 'Trivy Scan Job Failures (30m)' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Trivy Operator Job Reconcile Errors' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '{namespace=\"trivy-system\",pod=~\"trivy-operator.*\"} | json | controller=\"job\" | msg=\"Reconciler error\"' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'sum(increase(kube_job_status_failed{namespace=\"trivy-system\",job_name=~\"scan-.*\"}[30m]))' "${DASH}"
  [ "${status}" -eq 0 ]
}

@test "trivy observability: prometheus rule and alertmanager route cover scan job failures" {
  run grep -F -- 'TrivyOperatorScanJobFailures' "${RULE}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'group: trivy-operator' "${RULE}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'sum(increase(kube_job_status_failed{namespace="trivy-system",job_name=~"scan-.*"}[10m])) > 0' "${RULE}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'TrivyOperatorScanJobFailures' "${ROUTE}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'https://webhook.3ai-talk.org/api/v1/analyze' "${ROUTE}"
  [ "${status}" -eq 0 ]
}
