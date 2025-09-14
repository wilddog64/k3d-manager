#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/eso.sh"
  RUN_LOG="$BATS_TEST_TMPDIR/run.log"
  : > "$RUN_LOG"
  RUN_EXIT_CODES=()
  _run_command() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit) shift ;;
        --) shift; break ;;
        *) break ;;
      esac
    done
    echo "$*" >> "$RUN_LOG"
    local rc=0
    if ((${#RUN_EXIT_CODES[@]})); then
      rc=${RUN_EXIT_CODES[0]}
      RUN_EXIT_CODES=("${RUN_EXIT_CODES[@]:1}")
    fi
    return "$rc"
  }
  export -f _run_command
  export_stubs
}

@test "Skips install if ESO already present" {
  RUN_EXIT_CODES=(0)
  run deploy_eso test-ns test-release
  [ "$status" -eq 0 ]
  [ "$output" = "ESO already installed in namespace test-ns" ]
  read_lines "$RUN_LOG" run_calls
  [ "${run_calls[0]}" = "helm -n test-ns status test-release" ]
  [ ! -s "$HELM_LOG" ]
  [ ! -s "$KUBECTL_LOG" ]
}

@test "Fresh install" {
  RUN_EXIT_CODES=(1)
  run deploy_eso sample-ns
  [ "$status" -eq 0 ]
  read_lines "$RUN_LOG" run_calls
  [ "${run_calls[0]}" = "helm -n sample-ns status external-secrets" ]
  mapfile -t helm_calls < "$HELM_LOG"
  [ "${helm_calls[0]}" = "repo add external-secrets https://charts.external-secrets.io" ]
  [ "${helm_calls[1]}" = "repo update" ]
  [[ "${helm_calls[2]}" == upgrade\ --install\ -n\ sample-ns\ external-secrets\ external-secrets/external-secrets\ --create-namespace\ --set\ installCRDs=true ]]
  read_lines "$RUN_LOG" run_calls
  [ "${kubectl_calls[0]}" = "-n sample-ns rollout status deploy/external-secrets --timeout=120s" ]
}
