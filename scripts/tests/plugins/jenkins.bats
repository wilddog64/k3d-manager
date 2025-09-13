#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/jenkins.sh"
  export_stubs
}

@test "Namespace creation" {
  KUBECTL_EXIT_CODES=(1 0)
  run _create_jenkins_namespace test-ns
  [ "$status" -eq 0 ]
  mapfile -t kubectl_calls < "$KUBECTL_LOG"
  [[ "${kubectl_calls[1]}" == apply* ]]
  [[ "$output" == *"Namespace test-ns created"* ]]
}

@test "PV/PVC setup" {
  KUBECTL_EXIT_CODES=(1 0)
  jhp="$SCRIPT_DIR/storage/jenkins_home"
  echo "JENKINS_HOME_PATH=$jhp"
  rm -rf "$jhp"
  run _create_jenkins_pv_pvc test-ns
  [ "$status" -eq 0 ]
  [[ -d "$jhp" ]]
  mapfile -t kubectl_calls < "$KUBECTL_LOG"
  [[ "${kubectl_calls[1]}" == apply* ]]
}

@test "Full deployment" {
  CALLS_LOG="$BATS_TEST_TMPDIR/calls.log"
  : > "$CALLS_LOG"
  deploy_vault() { :; }
  _create_jenkins_admin_vault_policy() { :; }
  _create_jenkins_vault_ad_policy() { :; }
  _create_jenkins_namespace() { echo "_create_jenkins_namespace" >> "$CALLS_LOG"; }
  _deploy_jenkins() { echo "_deploy_jenkins" >> "$CALLS_LOG"; }
  run deploy_jenkins sample-ns
  [ "$status" -eq 0 ]
  mapfile -t calls < "$CALLS_LOG"
  [ "${#calls[@]}" -eq 2 ]
  [ "${calls[0]}" = "_create_jenkins_namespace" ]
  [ "${calls[1]}" = "_deploy_jenkins" ]
}
