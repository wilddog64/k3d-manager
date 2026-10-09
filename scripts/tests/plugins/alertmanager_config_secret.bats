#!/usr/bin/env bats

setup() {
  ETC_DIR="${BATS_TEST_DIRNAME}/../../etc"
  OBSERVABILITY_PLUGIN="${OBSERVABILITY_PLUGIN:-${BATS_TEST_DIRNAME}/../../plugins/observability.sh}"
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

@test "Grafana ServiceMonitors carry the release label Prometheus selects" {
  local values expected
  for values in \
    "${ETC_DIR}/helm/observability/kube-prometheus-stack-values.yaml" \
    "${ETC_DIR}/helm/observability/kube-prometheus-stack-acg-values.yaml"; do
    expected="$(basename "${values}" | sed 's/-values.yaml//' | sed 's/^kube-prometheus-stack$/kube-prometheus-stack/' | sed 's/^kube-prometheus-stack-acg$/acg-kube-prometheus-stack/')"
    run yq -r '.grafana.serviceMonitor.labels.release' "${values}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${expected}" ]
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

  run yq -r '.route.routes[2].receiver' "${tmpl}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "sms-critical" ]
}

@test "Alertmanager sends ACG sandbox criticals to email, not SMS" {
  local tmpl="${ETC_DIR}/prometheus/alertmanager.yaml.tmpl"

  run yq -r '.route.routes[1].receiver' "${tmpl}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "platform-warning" ]

  run yq -r '.route.routes[1].matchers[]' "${tmpl}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"severity = critical"* ]]
  [[ "${output}" == *'cluster =~ "acg|ubuntu-k3s"'* ]]

  run yq -r '.route.routes[2].matchers[0]' "${tmpl}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "severity = critical" ]

  run yq -r '.route.routes[2].receiver' "${tmpl}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "sms-critical" ]
}

@test "Alertmanager amtool routes ACG sandbox criticals to email" {
  command -v amtool >/dev/null 2>&1 || skip "amtool is not installed"

  local tmpl="${ETC_DIR}/prometheus/alertmanager.yaml.tmpl"
  local rendered="${BATS_TEST_TMPDIR}/alertmanager.yaml"
  env ALERTMANAGER_GMAIL_FROM=a@example.com \
    ALERTMANAGER_GMAIL_APP_PASSWORD=x \
    ALERTMANAGER_SMS_GATEWAY=1234567890@example.com \
    envsubst < "${tmpl}" > "${rendered}"

  run amtool config routes test --config.file="${rendered}" severity=critical cluster=ubuntu-k3s
  [ "${status}" -eq 0 ]
  [ "${output}" = "platform-warning" ]

  run amtool config routes test --config.file="${rendered}" severity=critical cluster=acg
  [ "${status}" -eq 0 ]
  [ "${output}" = "platform-warning" ]

  run amtool config routes test --config.file="${rendered}" severity=critical cluster=hub
  [ "${status}" -eq 0 ]
  [ "${output}" = "sms-critical" ]

  run amtool config routes test --config.file="${rendered}" alertname=TrivyCriticalVulnerabilityDetected severity=critical cluster=hub
  [ "${status}" -eq 0 ]
  [ "${output}" = "null" ]
}

@test "Alertmanager routes KubeJobFailed to platform-warning" {
  local tmpl="${ETC_DIR}/prometheus/alertmanager.yaml.tmpl"

  run yq -r '.route.routes[3].matchers[0]' "${tmpl}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"KubeJobFailed"* ]]

  run yq -r '.route.routes[3].receiver' "${tmpl}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "platform-warning" ]
}

@test "Alertmanager platform-warning has a non-empty recipient after envsubst" {
  local tmpl="${ETC_DIR}/prometheus/alertmanager.yaml.tmpl"
  local rendered="${BATS_TEST_TMPDIR}/alertmanager.yaml"

  run env ALERTMANAGER_GMAIL_FROM=operator@example.com envsubst < "${tmpl}"
  [ "${status}" -eq 0 ]
  printf '%s\n' "${output}" > "${rendered}"

  run yq -r '.receivers[] | select(.name == "platform-warning") | .email_configs[0].to' "${rendered}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "operator@example.com" ]
}

@test "Alertmanager keeps the critical route before platform-warning" {
  local tmpl="${ETC_DIR}/prometheus/alertmanager.yaml.tmpl"

  run yq -r '.route.routes[2].receiver + " " + .route.routes[3].receiver' "${tmpl}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "sms-critical platform-warning" ]
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
  [ "${output}" = "1" ]
}

@test "Alertmanager config helper applies the secret without exposing the password" {
  local stub_dir="${BATS_TEST_TMPDIR}/bin" log="${BATS_TEST_TMPDIR}/kubectl.log"
  mkdir -p "${stub_dir}"
  cat > "${stub_dir}/kubectl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${KUBECTL_LOG}"
if [[ "$*" == *"get secret vault-root"* ]]; then
  printf 'dG9rZW4='
elif [[ "$*" == *"apply"* ]]; then
  cat >/dev/null
fi
EOF
  cat > "${stub_dir}/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s' '{"data":{"data":{"gmail_from":"a@example.invalid","gmail_app_pw":"SENTINEL-PW","sms_gateway":"s@example.invalid"}}}'
EOF
  chmod +x "${stub_dir}/kubectl" "${stub_dir}/curl"
  run env PATH="${stub_dir}:${PATH}" KUBECTL_LOG="${log}" OBSERVABILITY_PLUGIN="${OBSERVABILITY_PLUGIN}" \
    bash -c '
      _info() { :; }
      _warn() { :; }
      _kubectl() { kubectl "$@"; }
      export PLUGINS_DIR=/nonexistent SCRIPT_DIR="${1%/scripts/plugins/observability.sh}"
      source "${OBSERVABILITY_PLUGIN}"
      _observability_apply_alertmanager_config ctx-x
    ' _ "${BATS_TEST_DIRNAME}/../../.."
  [ "${status}" -eq 0 ]
  [[ "$(cat "${log}")" == *"create secret generic alertmanager-smtp-secret --context ctx-x"* ]]
  [[ "${output}" != *"SENTINEL-PW"* ]]
}

@test "missing Alertmanager Vault secret fails the helper and public command" {
  local stub_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${stub_dir}"
  cat > "${stub_dir}/kubectl" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"get secret vault-root"* ]]; then printf 'dG9rZW4='; fi
EOF
  cat > "${stub_dir}/curl" <<'EOF'
#!/usr/bin/env bash
exit 22
EOF
  chmod +x "${stub_dir}/kubectl" "${stub_dir}/curl"
  run env PATH="${stub_dir}:${PATH}" OBSERVABILITY_PLUGIN="${OBSERVABILITY_PLUGIN}" \
    bash -c '
      _info() { :; }
      _warn() { :; }
      _kubectl() { kubectl "$@"; }
      export PLUGINS_DIR=/nonexistent SCRIPT_DIR="${1%/scripts/plugins/observability.sh}"
      source "${OBSERVABILITY_PLUGIN}"
      _observability_apply_alertmanager_config ctx-x && exit 1
      observability_alertmanager_config && exit 1
      true
    ' _ "${BATS_TEST_DIRNAME}/../../.."
  [ "${status}" -eq 0 ]
}

@test "Alertmanager config helper does not leak credentials into the calling shell" {
  local stub_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${stub_dir}"
  cat > "${stub_dir}/kubectl" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"get secret vault-root"* ]]; then printf 'dG9rZW4='; fi
EOF
  cat > "${stub_dir}/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s' '{"data":{"data":{"gmail_from":"a@example.invalid","gmail_app_pw":"SENTINEL-PW","sms_gateway":"s@example.invalid"}}}'
EOF
  chmod +x "${stub_dir}/kubectl" "${stub_dir}/curl"
  run env PATH="${stub_dir}:${PATH}" OBSERVABILITY_PLUGIN="${OBSERVABILITY_PLUGIN}" \
    bash -c '
      unset ALERTMANAGER_GMAIL_APP_PW
      _info() { :; }
      _warn() { :; }
      _kubectl() { kubectl "$@"; }
      export PLUGINS_DIR=/nonexistent SCRIPT_DIR="${1%/scripts/plugins/observability.sh}"
      source "${OBSERVABILITY_PLUGIN}"
      declare -F _observability_apply_alertmanager_config >/dev/null || exit 1
      _observability_apply_alertmanager_config ctx-x >/dev/null
      [[ -z "${ALERTMANAGER_GMAIL_APP_PW+x}" ]]
    ' _ "${BATS_TEST_DIRNAME}/../../.."
  [ "${status}" -eq 0 ]
}

@test "Alertmanager template has one render site" {
  run grep -c 'alertmanager.yaml.tmpl' "${OBSERVABILITY_PLUGIN}"
  [ "${status}" -eq 0 ]
  [ "${output}" -eq 1 ]
}

@test "make alertmanager-config invokes the public command" {
  run make -n -s -C "${BATS_TEST_DIRNAME}/../../.." alertmanager-config
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"observability_alertmanager_config"* ]]
}
