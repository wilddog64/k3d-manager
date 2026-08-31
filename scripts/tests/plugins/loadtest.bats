#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  export SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${SCRIPT_DIR}/plugins/loadtest.sh"
  export LOADTEST_STAGES="100 250 500 1000 2500 5000"
  export LOADTEST_MAX_ERROR_RATE=2 LOADTEST_MAX_P95_SECONDS=2 LOADTEST_MAX_CPU_PCT=80
  export LOADTEST_BREACH_INTERVALS=2
}

@test "loadtest: green gates increase and reset breach count" {
  run _loadtest_decide 0 "" 1
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "increase" ]
  [ "${lines[1]}" = "0" ]
}

@test "loadtest: first breach holds with hysteresis" {
  run _loadtest_decide 0 "error_rate" 0
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "hold" ]
  [ "${lines[1]}" = "1" ]
}

@test "loadtest: second consecutive breach stops" {
  run _loadtest_decide 0 "error_rate" 1
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "stop" ]
  [ "${lines[1]}" = "2" ]
}

@test "loadtest: each hard stop condition appears in breach list" {
  run _loadtest_evaluate_gates 2.5 2 80 0 0 0 0 0
  [[ "${output}" == *error_rate* ]]
  run _loadtest_evaluate_gates 2 2.1 80 0 0 0 0 0
  [[ "${output}" == *p95_seconds* ]]
  run _loadtest_evaluate_gates 2 2 81 0 0 0 0 0
  [[ "${output}" == *cpu_pct* ]]
  for flag in stripe_rate_limited db_pool_exhausted control_plane_error node_eviction_risk memory_pressure; do
    args=(2 2 80 0 0 0 0 0)
    case "${flag}" in
      stripe_rate_limited) args[3]=1 ;;
      db_pool_exhausted) args[4]=1 ;;
      control_plane_error) args[5]=1 ;;
      node_eviction_risk) args[6]=1 ;;
      memory_pressure) args[7]=1 ;;
    esac
    run _loadtest_evaluate_gates "${args[@]}"
    [[ "${output}" == *"${flag}"* ]]
  done
}

@test "loadtest: strict thresholds keep 2/2/80 green" {
  run _loadtest_evaluate_gates 2 2 80 0 0 0 0 0
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "loadtest: stage ladder caps at 5000" {
  expected=(250 500 1000 2500 5000 5000)
  for index in 0 1 2 3 4 5; do
    run _loadtest_next_stage "${index}"
    [ "${output}" = "${expected[${index}]}" ]
  done
}

@test "loadtest: confirmation gate refuses without explicit opt-in" {
  unset LOADTEST_CONFIRM
  run loadtest_run
  [ "${status}" -ne 0 ]
  [[ "${output}" == *refusing* ]]
}

@test "loadtest: token endpoint is derived from the issuer" {
  run _loadtest_token_endpoint "https://kc.example/realms/shopping-cart"
  [ "${output}" = "https://kc.example/realms/shopping-cart/protocol/openid-connect/token" ]
  run _loadtest_token_endpoint "https://kc.example/realms/shopping-cart/"
  [ "${output}" = "https://kc.example/realms/shopping-cart/protocol/openid-connect/token" ]
}

@test "loadtest: mint token refuses without credentials" {
  unset LOADTEST_CLIENT_SECRET LOADTEST_USERNAME LOADTEST_PASSWORD
  run _loadtest_mint_token
  [ "${status}" -ne 0 ]
  [[ "${output}" == *LOADTEST_CLIENT_SECRET* ]]
}

@test "loadtest: prom query returns 0 for empty/failed result" {
  _loadtest_curl() { return 1; }
  run _loadtest_prom_query "up"
  [ "${status}" -eq 0 ]
  [ "${output}" = "0" ]
}

@test "loadtest: prom query parses a scalar value" {
  _loadtest_curl() { printf '{"data":{"result":[{"value":[0,"1.75"]}]}}'; }
  run _loadtest_prom_query "some_query"
  [ "${output}" = "1.75" ]
}

@test "loadtest: prom flag maps positive to 1 and zero to 0" {
  _loadtest_curl() { printf '{"data":{"result":[{"value":[0,"3"]}]}}'; }
  run _loadtest_prom_flag "q"
  [ "${output}" = "1" ]
  _loadtest_curl() { printf '{"data":{"result":[{"value":[0,"0"]}]}}'; }
  run _loadtest_prom_flag "q"
  [ "${output}" = "0" ]
}

@test "loadtest: fetch metrics emits the 8-positional snapshot" {
  _loadtest_curl() { printf '{"data":{"result":[{"value":[0,"0"]}]}}'; }
  run _loadtest_fetch_metrics
  [ "${status}" -eq 0 ]
  set -- ${output}
  [ "$#" -eq 8 ]
}

@test "loadtest: dry-run ramps through green stages and writes a summary each" {
  export LOADTEST_STAGES="100 250 500"
  export LOADTEST_RESULT_DIR="${BATS_TEST_TMPDIR}/results"
  export LOADTEST_RUN_ID="run-dry-green"
  export LOADTEST_DRY_METRICS="0 0 0 0 0 0 0 0"
  run loadtest_run --confirm --dry-run
  [ "${status}" -eq 0 ]
  [ -f "${LOADTEST_RESULT_DIR}/run-dry-green/stage-0-100.json" ]
  [ -f "${LOADTEST_RESULT_DIR}/run-dry-green/stage-2-500.json" ]
  jq -e '.decision == "increase"' "${LOADTEST_RESULT_DIR}/run-dry-green/stage-0-100.json"
}

@test "loadtest: dry-run stops after hysteresis on a persistent breach" {
  export LOADTEST_STAGES="100 250 500"
  export LOADTEST_RESULT_DIR="${BATS_TEST_TMPDIR}/results"
  export LOADTEST_RUN_ID="run-dry-breach"
  export LOADTEST_BREACH_INTERVALS=2
  export LOADTEST_DRY_METRICS="5 0 0 0 0 0 0 0"
  run loadtest_run --confirm --dry-run
  [ "${status}" -eq 0 ]
  [ -f "${LOADTEST_RESULT_DIR}/run-dry-breach/stage-0-100.json" ]
  [ -f "${LOADTEST_RESULT_DIR}/run-dry-breach/stage-1-250.json" ]
  [ ! -f "${LOADTEST_RESULT_DIR}/run-dry-breach/stage-2-500.json" ]
  jq -e '.decision == "stop"' "${LOADTEST_RESULT_DIR}/run-dry-breach/stage-1-250.json"
}

@test "loadtest: stage summary is valid and immutable" {
  summary="${BATS_TEST_TMPDIR}/stage.json"
  run _loadtest_write_stage_summary run-1 stage-100 100 98.5 hold "error_rate p95_seconds" "${summary}"
  [ "${status}" -eq 0 ]
  jq -e '.run_id == "run-1" and .target_concurrency == 100 and (.breaches | length) == 2' "${summary}"
  run _loadtest_write_stage_summary run-1 stage-100 100 98.5 stop "error_rate" "${summary}"
  [ "${status}" -ne 0 ]
}
