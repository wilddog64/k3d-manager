#!/usr/bin/env bats

APPSET="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/observability-acg.yaml"
VALUES="${BATS_TEST_DIRNAME}/../../etc/helm/observability/loki-values.yaml"
PROMTAIL="${BATS_TEST_DIRNAME}/../../etc/observability/promtail.yaml"
PLUGIN="${BATS_TEST_DIRNAME}/../../plugins/observability.sh"

@test "loki: observability-acg includes a loki application" {
  run grep -nF -- 'name: loki' "${APPSET}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'chart: loki' "${APPSET}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'grafana-community.github.io/helm-charts' "${APPSET}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'loki-values.yaml' "${APPSET}"
  [ "${status}" -eq 0 ]
}

@test "loki: values pin monolithic filesystem mode" {
  run grep -nF -- 'deploymentMode: Monolithic' "${VALUES}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'type: filesystem' "${VALUES}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'replication_factor: 1' "${VALUES}"
  [ "${status}" -eq 0 ]
}

@test "loki: promtail ships pod logs to Loki" {
  run grep -nF -- 'fluent/fluent-bit:latest' "${PROMTAIL}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'Host          loki.monitoring.svc.cluster.local' "${PROMTAIL}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'fluent-bit.conf' "${PROMTAIL}"
  [ "${status}" -eq 0 ]
}

@test "loki: observability deploy applies promtail manifest" {
  run grep -nF -- '_deploy_promtail_acg' "${PLUGIN}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'Loki/Promtail log shipper applied' "${PLUGIN}"
  [ "${status}" -eq 0 ]
}
