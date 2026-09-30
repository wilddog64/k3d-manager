#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/../.."
TEMPLATE="${ROOT}/etc/launchd/com.k3d-manager.hub-pushgateway-port-forward.plist.tmpl"
VALUES="${ROOT}/etc/helm/observability/pushgateway-hub-values.yaml"

@test "hub Pushgateway values use the stable service name" {
  run grep -F -- 'fullnameOverride: prometheus-pushgateway' "${VALUES}"
  [ "${status}" -eq 0 ]
}

@test "hub port-forward template uses 19094 and never 9091 to 9091" {
  run cat "${TEMPLATE}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"19094:9091"* ]]
  [[ "${output}" == *"svc/prometheus-pushgateway"* ]]
  [[ "${output}" == *"k3d-k3d-cluster"* ]]
  [[ "${output}" != *"9091:9091"* ]]
}

@test "make target renders the hub template without launching launchd" {
  run make -n install-hub-pushgateway-port-forward
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"com.k3d-manager.hub-pushgateway-port-forward.plist.tmpl"* ]]
  [[ "${output}" == *"sed"* ]]
}

@test "hub Prometheus scrapes the Pushgateway with honor_labels" {
  run python3 - "${ROOT}/etc/helm/observability/kube-prometheus-stack-values.yaml" <<'PY'
import sys
import yaml

values = yaml.safe_load(open(sys.argv[1]))
jobs = values["prometheus"]["prometheusSpec"]["additionalScrapeConfigs"]
job = next(item for item in jobs if item["job_name"] == "pushgateway")
assert job["honor_labels"] is True
assert job["static_configs"][0]["targets"] == ["prometheus-pushgateway.monitoring:9091"]
PY
  [ "${status}" -eq 0 ]
}

@test "observability ApplicationSet pins the hub chart" {
  run grep -A6 -F -- 'name: hub-pushgateway' "${ROOT}/etc/argocd/applicationsets/observability.yaml"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"targetRevision: 2.14.0"* ]]
}
