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

@test "make alertmanager-secret rejects empty input without calling Vault" {
  local stub_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${stub_dir}"
  printf '#!/bin/sh\nprintf dG9rZW4=\n' > "${stub_dir}/kubectl"
  printf '#!/bin/sh\nexit 1\n' > "${stub_dir}/security"
  printf '#!/bin/sh\ntouch "%s/curl-called"\n' "${BATS_TEST_TMPDIR}" > "${stub_dir}/curl"
  chmod +x "${stub_dir}/kubectl" "${stub_dir}/security" "${stub_dir}/curl"

  run env PATH="${stub_dir}:${PATH}" make -s -C "${BATS_TEST_DIRNAME}/../../.." alertmanager-secret < /dev/null
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"unresolved:"* ]]
  [[ "${output}" == *"gmail_from"* ]]
  [[ "${output}" == *"gmail_app_pw"* ]]
  [[ "${output}" == *"sms_gateway"* ]]
  [ ! -e "${BATS_TEST_TMPDIR}/curl-called" ]
}

@test "observability treats empty Alertmanager Vault values as absent" {
  run grep -c 'all(v) or sys.exit(1)' "${BATS_TEST_DIRNAME}/../../plugins/observability.sh"
  [ "${status}" -eq 0 ]
  [ "${output}" = "2" ]
}
