#!/usr/bin/env bats

VALUES="${BATS_TEST_DIRNAME}/../../etc/helm/observability/kube-prometheus-stack-values.yaml"
DASHBOARD="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-argocd.yaml"

@test "federate-acg drops self-scraped samples" {
  run yq -r '.prometheus.prometheusSpec.additionalScrapeConfigs[] | select(.job_name == "federate-acg") | .metric_relabel_configs[0].action' "${VALUES}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "drop" ]

  run yq -r '.prometheus.prometheusSpec.additionalScrapeConfigs[] | select(.job_name == "federate-acg") | .metric_relabel_configs[0].source_labels[0]' "${VALUES}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "cluster" ]

  run yq -r '.prometheus.prometheusSpec.additionalScrapeConfigs[] | select(.job_name == "federate-acg") | .metric_relabel_configs[0].regex' "${VALUES}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "acg" ]
}

@test "federate-acg labels the target acg and honors source labels" {
  run yq -r '.prometheus.prometheusSpec.additionalScrapeConfigs[] | select(.job_name == "federate-acg") | .static_configs[0].labels.cluster' "${VALUES}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "acg" ]

  run yq -r '.prometheus.prometheusSpec.additionalScrapeConfigs[] | select(.job_name == "federate-acg") | .honor_labels' "${VALUES}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "true" ]
}

@test "image updater replica stats aggregate" {
  local dashboard_json
  local ready_expr
  local desired_expr

  dashboard_json="$(yq -r '.data["argocd-image-updater-hub.json"]' "${DASHBOARD}")"
  ready_expr="$(jq -r '.panels[] | select(.title == "Image Updater Ready Replicas") | .targets[0].expr' <<<"${dashboard_json}")"
  desired_expr="$(jq -r '.panels[] | select(.title == "Image Updater Desired Replicas") | .targets[0].expr' <<<"${dashboard_json}")"

  [[ "${ready_expr}" == max\(* ]]
  [[ "${ready_expr}" == *'cluster!="acg"'* ]]
  [[ "${desired_expr}" == max\(* ]]
  [[ "${desired_expr}" == *'cluster!="acg"'* ]]
}

@test "argocd dashboard JSON parses" {
  run bash -c 'yq -r '\'' .data["argocd-image-updater-hub.json"] '\'' "$1" | jq -e '\''.panels | length > 0'\''' _ "${DASHBOARD}"
  [ "${status}" -eq 0 ]
}
