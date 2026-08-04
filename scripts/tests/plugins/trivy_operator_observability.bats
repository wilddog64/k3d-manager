#!/usr/bin/env bats

SETTINGS="${BATS_TEST_DIRNAME}/../../etc/helm/observability/trivy-operator-values.yaml"
ACG_SETTINGS="${BATS_TEST_DIRNAME}/../../etc/helm/observability/trivy-operator-acg-values.yaml"
HUB_APPSET="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/observability.yaml"
ACG_APPSET="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/observability-acg.yaml"
DASH="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-argocd.yaml"
TRIVY_DASH="${BATS_TEST_DIRNAME}/../../etc/grafana/dashboards/trivy-security-configmap.yaml"
RULE="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/prometheusrule.yaml"
ROUTE="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/alertmanager-config.yaml"

@test "trivy observability: charts pin trivy-operator 0.34.0 in both application sets" {
  run grep -F -- 'targetRevision: 0.34.0' "${HUB_APPSET}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'targetRevision: 0.34.0' "${ACG_APPSET}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'targetRevision: 0.33.2' "${HUB_APPSET}"
  [ "${status}" -ne 0 ]

  run grep -F -- 'targetRevision: 0.33.2' "${ACG_APPSET}"
  [ "${status}" -ne 0 ]
}

@test "trivy observability: chart values enable serviceMonitor scraping" {
  run grep -F -- 'registry: mirror.gcr.io' "${SETTINGS}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'repository: aquasec/trivy-operator' "${SETTINGS}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'tag: "0.32.0"' "${SETTINGS}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'tag: "0.32.0"' "${ACG_SETTINGS}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'tag: "0.31.2"' "${SETTINGS}"
  [ "${status}" -ne 0 ]

  run grep -F -- 'tag: "0.31.2"' "${ACG_SETTINGS}"
  [ "${status}" -ne 0 ]

  run grep -F -- 'serviceMonitor:' "${SETTINGS}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'enabled: true' "${SETTINGS}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'release: kube-prometheus-stack' "${SETTINGS}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'release: acg-kube-prometheus-stack' "${ACG_SETTINGS}"
  [ "${status}" -eq 0 ]
}

@test "trivy observability: scanner image tag is explicitly pinned in both values files" {
  run grep -F -- 'tag: "0.72.0"' "${SETTINGS}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'tag: "0.72.0"' "${ACG_SETTINGS}"
  [ "${status}" -eq 0 ]
}

@test "trivy observability: both values files enable the built-in trivy server (ClientServer mode)" {
  run grep -F -- 'builtInTrivyServer: true' "${SETTINGS}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'builtInTrivyServer: true' "${ACG_SETTINGS}"
  [ "${status}" -eq 0 ]
}

@test "trivy observability: acg trivy application set uses the acg-specific values file" {
  run grep -F -- 'valuesFile: scripts/etc/helm/observability/trivy-operator-acg-values.yaml' "${ACG_APPSET}"
  [ "${status}" -eq 0 ]
}

@test "trivy observability: dashboard exposes log and metric panels for trivy-system" {
  run grep -F -- 'Trivy Scan Job Failures (30m)' "${TRIVY_DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Trivy Operator Job Reconcile Errors' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '{namespace=\"trivy-system\",pod=~\"trivy-operator.*\"} | json | level=\"error\"' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'msg=\"Reconciler error\"' "${DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- 'sum(increase(kube_job_status_failed{namespace=\"trivy-system\",job_name=~\"scan-.*\"}[30m]))' "${TRIVY_DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Trivy Cluster Compliance Failures' "${DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- 'Trivy Cluster Compliance Failures' "${TRIVY_DASH}"
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

@test "trivy observability: critical alerts populate legacy app notification label" {
  run grep -F -- 'app: "{{ $labels.image_repository }}"' "${RULE}"
  [ "${status}" -eq 0 ]
}
