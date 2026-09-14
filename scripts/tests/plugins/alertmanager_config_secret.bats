#!/usr/bin/env bats

setup() {
  ETC_DIR="${BATS_TEST_DIRNAME}/../../etc"
}

@test "kube-prometheus-stack values point Alertmanager at the SMTP secret" {
  local values
  for values in \
    "${ETC_DIR}/helm/observability/kube-prometheus-stack-values.yaml" \
    "${ETC_DIR}/helm/observability/kube-prometheus-stack-acg-values.yaml"; do
    run yq -r '.alertmanager.alertmanagerSpec.configSecret' "${values}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "alertmanager-smtp-secret" ]

    run yq -r '.alertmanager.alertmanagerSpec.useExistingSecret' "${values}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "true" ]

    run yq -r '.alertmanager.configSecret' "${values}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "null" ]
  done
}

@test "Alertmanager routes Trivy critical CVE alerts to null before SMS" {
  local tmpl="${ETC_DIR}/prometheus/alertmanager.yaml.tmpl"

  run yq -r '.route.routes[0].matchers[0]' "${tmpl}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "alertname = TrivyCriticalVulnerabilityDetected" ]

  run yq -r '.route.routes[0].receiver' "${tmpl}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "null" ]

  run yq -r '.route.routes[1].receiver' "${tmpl}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "sms-critical" ]
}
