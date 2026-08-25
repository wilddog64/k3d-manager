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

@test "loadtest: confirmation flag initializes without live calls" {
  run loadtest_run --confirm
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"not wired"* ]]
}

@test "loadtest: stage summary is valid and immutable" {
  summary="${BATS_TEST_TMPDIR}/stage.json"
  run _loadtest_write_stage_summary run-1 stage-100 100 98.5 hold "error_rate p95_seconds" "${summary}"
  [ "${status}" -eq 0 ]
  jq -e '.run_id == "run-1" and .target_concurrency == 100 and (.breaches | length) == 2' "${summary}"
  run _loadtest_write_stage_summary run-1 stage-100 100 98.5 stop "error_rate" "${summary}"
  [ "${status}" -ne 0 ]
}
