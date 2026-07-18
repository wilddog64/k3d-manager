#!/usr/bin/env bats

ACG="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/grafana-dashboards-acg.yaml"
HUB="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/grafana-dashboards-hub.yaml"
PLUGIN="${BATS_TEST_DIRNAME}/../../plugins/observability.sh"

@test "acg dashboard appset targets app-cluster role" {
  run yq -r '.spec.generators[0].clusters.selector.matchLabels["k3d-manager/role"]' "${ACG}"
  [ "$status" -eq 0 ]
  [ "$output" = "app-cluster" ]
}

@test "acg dashboard appset syncs the dashboards directory" {
  run yq -r '.spec.template.spec.source.path' "${ACG}"
  [ "$output" = "scripts/etc/grafana/dashboards" ]
}

@test "hub dashboard appset includes only the argocd dashboard" {
  run yq -r '.spec.template.spec.source.directory.include' "${HUB}"
  [ "$output" = "grafana-dashboard-argocd.yaml" ]
}

@test "both dashboard appsets self-heal" {
  run yq -r '.spec.template.spec.syncPolicy.automated.selfHeal' "${ACG}"
  [ "$output" = "true" ]
  run yq -r '.spec.template.spec.syncPolicy.automated.selfHeal' "${HUB}"
  [ "$output" = "true" ]
}

@test "observability plugin applies both dashboard appsets" {
  run grep -c 'grafana-dashboards-\(acg\|hub\).yaml' "${PLUGIN}"
  [ "$output" = "2" ]
}
