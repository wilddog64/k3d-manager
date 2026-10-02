#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  TEMPLATE="${REPO_ROOT}/scripts/etc/istio-operator.yaml.tmpl"
  RENDERED="${BATS_TEST_TMPDIR}/istio-operator.yaml"

  export PILOT_K8S_CPU=100m
  export PILOT_K8S_MEM=256Mi
  export ING_K8S_CPU=100m
  export ING_K8S_MEM=256Mi
  export GLO_PROXY_CPU=50m
  export GLO_PROXY_MEM=64Mi

  envsubst < "${TEMPLATE}" > "${RENDERED}"
}

@test "Istio operator template renders valid YAML without HPAs" {
  run yq -e '.' "${RENDERED}"
  [ "${status}" -eq 0 ]
  [ -z "$(yq -r '.. | select(has("hpaSpec"))' "${RENDERED}")" ]
  [ "$(yq -r '.spec.components.pilot.k8s.replicaCount' "${RENDERED}")" = "1" ]
  [ "$(yq -r '.spec.components.ingressGateways[] | select(.name == "istio-ingressgateway") | .k8s.replicaCount' "${RENDERED}")" = "1" ]
  [ "$(yq -r '.spec.values.pilot.autoscaleEnabled' "${RENDERED}")" = "false" ]
  [ "$(yq -r '.spec.values.gateways.istio-ingressgateway.autoscaleEnabled' "${RENDERED}")" = "false" ]
}

@test "Istio operator template preserves component resources" {
  [ "$(yq -r '.spec.components.pilot.k8s.resources.limits.cpu' "${RENDERED}")" = "500m" ]
  [ "$(yq -r '.spec.components.pilot.k8s.resources.limits.memory' "${RENDERED}")" = "1Gi" ]
  [ "$(yq -r '.spec.components.ingressGateways[] | select(.name == "istio-ingressgateway") | .k8s.resources.limits.cpu' "${RENDERED}")" = "500m" ]
  [ "$(yq -r '.spec.components.ingressGateways[] | select(.name == "istio-ingressgateway") | .k8s.resources.limits.memory' "${RENDERED}")" = "512Mi" ]
}
