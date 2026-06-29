#!/usr/bin/env bats

APPSET="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/observability-acg.yaml"
HUB_APPSET="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/observability.yaml"
VALUES="${BATS_TEST_DIRNAME}/../../etc/helm/observability/loki-values.yaml"
PROM_VALUES="${BATS_TEST_DIRNAME}/../../etc/helm/observability/kube-prometheus-stack-values.yaml"
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

@test "loki: hub observability includes a loki application" {
  run grep -nF -- 'name: hub-loki' "${HUB_APPSET}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'chart: loki' "${HUB_APPSET}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'grafana-community.github.io/helm-charts' "${HUB_APPSET}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'loki-values.yaml' "${HUB_APPSET}"
  [ "${status}" -eq 0 ]
}

@test "loki: hub observability forces the helm release name back to loki" {
  run grep -nF -- "releaseName: '{{if eq .name \"hub-loki\"}}loki{{else}}{{.name}}{{end}}'" "${HUB_APPSET}"
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

@test "loki: hub grafana provisions a loki datasource" {
  run grep -nF -- 'name: Loki' "${PROM_VALUES}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'uid: loki' "${PROM_VALUES}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'url: http://hub-loki-gateway.monitoring.svc.cluster.local' "${PROM_VALUES}"
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

@test "loki: hub observability deploy applies the argocd image updater dashboard" {
  run grep -nF -- '_observability_apply_argocd_dashboard "${_hub_context}"' "${PLUGIN}"
  [ "${status}" -eq 0 ]

  run grep -nF -- 'ArgoCD/Image Updater dashboard applied on' "${PLUGIN}"
  [ "${status}" -eq 0 ]
}
