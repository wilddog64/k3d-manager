#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/eso.sh"
  export_stubs
}

@test "Skips install if ESO already present" {
  RUN_EXIT_CODES=(0)
  run deploy_eso test-ns test-release
  [ "$status" -eq 0 ]
  [ "$output" = "ESO already installed in namespace test-ns" ]
  mapfile -t run_calls < "$RUN_LOG"
  [ "${run_calls[0]}" = "helm -n test-ns status test-release" ]
  [ ! -s "$HELM_LOG" ]
  [ ! -s "$KUBECTL_LOG" ]
}

@test "Installs ESO when absent" {
  RUN_EXIT_CODES=(1)
  run deploy_eso test-ns test-release
  [ "$status" -eq 0 ]
  mapfile -t run_calls < "$RUN_LOG"
  [ "${run_calls[0]}" = "helm -n test-ns status test-release" ]
  mapfile -t helm_calls < "$HELM_LOG"
  [ "${helm_calls[0]}" = "repo add external-secrets https://charts.external-secrets.io" ]
  [ "${helm_calls[1]}" = "repo update" ]
  [[ "${helm_calls[2]}" == upgrade* ]]
  mapfile -t kubectl_calls < "$KUBECTL_LOG"
  [ "${kubectl_calls[0]}" = "-n test-ns rollout status deploy/external-secrets --timeout=120s" ]
}
