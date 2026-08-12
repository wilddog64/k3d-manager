#!/usr/bin/env bats

setup() {
  STATUS_SCRIPT="${BATS_TEST_DIRNAME}/../../../bin/cluster-status-summary"
  TMP_DIR="$(mktemp -d)"
  cat >"${TMP_DIR}/curl" <<'EOF'
#!/bin/sh
cat <<'JSON'
{"services":[{"name":"shopping-cart-order","ok":false,"detail":"HTTP 503; readiness 0/1"},{"name":"Pushgateway","ok":false,"detail":"connection refused"},{"name":"Grafana","ok":true,"detail":"HTTP 200"}]}
JSON
EOF
  chmod +x "${TMP_DIR}/curl"
  export PATH="${TMP_DIR}:${PATH}" K3DM_WEBHOOK_TOKEN=test STATUS_COLOR=never
}

teardown() { rm -rf "${TMP_DIR}"; }

@test "summary reports failed services before healthy checks" {
  run "${STATUS_SCRIPT}" --mode summary
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"shopping-cart-order: HTTP 503; readiness 0/1"* ]]
  [[ "${output}" == *"Grafana: HTTP 200"* ]]
  [[ "${output}" == *"Overall: FAIL"* ]]
  [[ "${output}" == *"Pushgateway: connection refused"* ]]
}

@test "focused service mode excludes unrelated services" {
  run "${STATUS_SCRIPT}" --mode summary --service shopping-cart-order
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"shopping-cart-order"* ]]
  [[ "${output}" != *"Grafana"* ]]
}

@test "json mode contains structured statuses and no ANSI" {
  run "${STATUS_SCRIPT}" --mode json
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'"http_code"'* ]]
  [[ "${output}" != *$'\033['* ]]
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["overall"] == "fail"; assert d["counts"]["services_failed"] == 1' "${output}"
}

@test "unknown service returns usage error" {
  run "${STATUS_SCRIPT}" --mode summary --service not-a-service
  [ "${status}" -eq 3 ]
  [[ "${output}" == *"unknown service"* ]]
}
