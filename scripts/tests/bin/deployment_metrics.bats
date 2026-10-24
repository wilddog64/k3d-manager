#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  export REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  export TEST_ROOT="$(mktemp -d)"
  export CURL_LOG="${TEST_ROOT}/curl.log"
  export CURL_PAYLOAD="${TEST_ROOT}/payload.txt"
  mkdir -p "${TEST_ROOT}/bin"
  : > "${CURL_LOG}"
  : > "${CURL_PAYLOAD}"
  cat > "${TEST_ROOT}/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${CURL_LOG}"
cat > "${CURL_PAYLOAD}"
exit "${CURL_RC:-0}"
STUB
  chmod +x "${TEST_ROOT}/bin/curl"
  export PATH="${TEST_ROOT}/bin:${PATH}"
  export K3DM_DEPLOYMENT_PUSHGATEWAY_URL="http://127.0.0.1:9"
}
teardown() {
  rm -rf "${TEST_ROOT}"
}

run_publisher() {
  run env REPO="${REPO}" bash -c '
    source "${REPO}/scripts/lib/system.sh"
    source "${REPO}/scripts/lib/deployment_metrics.sh"
    _k3dm_push_deployment_metrics "$@"
  ' bash "$@"
}

@test "E1: success publishes all three CLI series with webhook labels" {
  run_publisher up k3s-aws success 12 cli-123-456
  [ "${status}" -eq 0 ]
  grep -q 'metrics/job/k3dm-cli/instance/up-aws' "${CURL_LOG}"
  grep -q -- '--silent --show-error --max-time 5 --data-binary @-' "${CURL_LOG}"
  grep -q 'k3dm_deployment_duration_seconds{action="up",provider="aws",status="success",job_id="cli-123-456"} 12' "${CURL_PAYLOAD}"
  grep -q 'k3dm_deployment_last_timestamp_seconds{action="up",provider="aws",status="success"}' "${CURL_PAYLOAD}"
  grep -q 'k3dm_deployment_success{action="up",provider="aws",job_id="cli-123-456"} 1' "${CURL_PAYLOAD}"
}

@test "E1: failed publishes zero success and maps every provider" {
  for provider in k3s-aws k3s-gcp k3s-az; do
    run_publisher down "${provider}" failed 3 cli-123-456
    [ "${status}" -eq 0 ]
    case "${provider}" in
      k3s-aws) short=aws ;;
      k3s-gcp) short=gcp ;;
      k3s-az) short=azure ;;
    esac
    grep -q "metrics/job/k3dm-cli/instance/down-${short}" "${CURL_LOG}"
    grep -q 'status="failed"' "${CURL_PAYLOAD}"
    grep -q '} 0$' "${CURL_PAYLOAD}"
  done
}

@test "E1/N2: Pushgateway failure is non-fatal and warns without payload" {
  CURL_RC=7 run_publisher up k3s-gcp failed 1 cli-123-456
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"127.0.0.1:9"* ]]
}

@test "E1/N3: metrics disable and dry run skip curl" {
  K3DM_DEPLOYMENT_METRICS=0 run_publisher up k3s-aws success 1 cli-123-456
  [ "${status}" -eq 0 ]
  [ ! -s "${CURL_LOG}" ]
  DRY_RUN=1 run_publisher up k3s-aws success 1 cli-123-456
  [ "${status}" -eq 0 ]
  [ ! -s "${CURL_LOG}" ]
}

@test "E2: dashboard uses the prometheus datasource uid everywhere" {
  dashboard="${REPO}/scripts/etc/grafana/dashboards/k3dm-deployments-configmap.yaml"
  run grep -F 'P5A1115AEDF367D43' "${dashboard}"
  [ "${status}" -ne 0 ]
  [ "$(grep -c '"uid": "prometheus"' "${dashboard}")" -eq 5 ]
  run grep -F '"datasource": { "type": "prometheus", "uid": "prometheus" }' "${dashboard}"
  [ "${status}" -eq 0 ]
}

@test "N5: under BATS with no explicit URL the publisher never calls curl" {
  unset K3DM_DEPLOYMENT_PUSHGATEWAY_URL
  run_publisher down k3s-aws failed 0 test-run
  [ "${status}" -eq 0 ]
  [ ! -s "${CURL_LOG}" ]
}
