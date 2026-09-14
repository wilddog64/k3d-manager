#!/usr/bin/env bats

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
VALUES="${REPO_ROOT}/scripts/etc/helm/observability/kube-prometheus-stack-values.yaml"
HUB_PLIST="${REPO_ROOT}/scripts/etc/launchd/com.k3d-manager.prometheus-port-forward.plist.tmpl"
CLOUDFLARED_CONFIG="${REPO_ROOT}/scripts/etc/cloudflared/config.yml"

@test "app-cluster Prometheus forwards use 19190 plus provider offset" {
  run grep -q '19190 + $(\_acg_provider_port_offset' "${REPO_ROOT}/bin/cluster-up"
  [ "${status}" -eq 0 ]

  run grep -q '19090 + $(\_acg_provider_port_offset' "${REPO_ROOT}/bin/cluster-up"
  [ "${status}" -ne 0 ]

  run grep -q '"${_acg_prom_local_port}:9090"' "${REPO_ROOT}/bin/cluster-refresh"
  [ "${status}" -eq 0 ]

  run grep -c 'prometheus-operated 19090:9090' "${REPO_ROOT}/bin/cluster-refresh"
  [ "${status}" -ne 0 ]
  [ "${output}" -eq 0 ]
}

@test "federation and Grafana datasource use the app-cluster Prometheus port" {
  run yq -r '.prometheus.prometheusSpec.additionalScrapeConfigs[] | select(.job_name == "federate-acg") | .static_configs[0].targets[0]' "${VALUES}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "host.internal:19190" ]

  run yq -r '.grafana.additionalDataSources[] | select(.name == "acg-prometheus") | .url' "${VALUES}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "http://host.internal:19190" ]
}

@test "hub Prometheus port remains unchanged" {
  run grep -q '19090:9090' "${HUB_PLIST}"
  [ "${status}" -eq 0 ]

  run grep -q 'k3d-k3d-cluster' "${HUB_PLIST}"
  [ "${status}" -eq 0 ]

  run grep -q '127.0.0.1:19090' "${CLOUDFLARED_CONFIG}"
  [ "${status}" -eq 0 ]
}

@test "webhook and load-test defaults use the app-cluster Prometheus port" {
  run grep -q 'localhost:19190' "${REPO_ROOT}/scripts/plugins/loadtest.sh"
  [ "${status}" -eq 0 ]

  run grep -q 'localhost:19190/-/ready' "${REPO_ROOT}/bin/k3dm-webhook"
  [ "${status}" -eq 0 ]
}
