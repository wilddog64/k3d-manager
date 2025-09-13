setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  source "${BATS_TEST_DIRNAME}/../../plugins/vault.sh"

  init_test_env
  export_stubs
}

@test "Namespace ensure" {
  KUBECTL_EXIT_CODES=(1 0)
  run _vault_ns_ensure test-ns
  [ "$status" -eq 0 ]
  mapfile -t kubectl_calls < "$KUBECTL_LOG"
  [ "${kubectl_calls[1]}" = "create ns test-ns" ]
}

@test "deploy_vault orchestrates steps" {
  CALLS_LOG="$BATS_TEST_TMPDIR/calls.log"
  : > "$CALLS_LOG"
  deploy_eso() { echo "deploy_eso" >> "$CALLS_LOG"; }
  _vault_ns_ensure() { echo "_vault_ns_ensure" >> "$CALLS_LOG"; }
  _vault_repo_setup() { echo "_vault_repo_setup" >> "$CALLS_LOG"; }
  _deploy_vault_ha() { echo "_deploy_vault_ha" >> "$CALLS_LOG"; }
  _vault_bootstrap_ha() { echo "_vault_bootstrap_ha" >> "$CALLS_LOG"; }
  _enable_kv2_k8s_auth() { echo "_enable_kv2_k8s_auth" >> "$CALLS_LOG"; }
  run deploy_vault ha sample-ns
  [ "$status" -eq 0 ]
  mapfile -t calls < "$CALLS_LOG"
  expected=(deploy_eso _vault_ns_ensure _vault_repo_setup _deploy_vault_ha _vault_bootstrap_ha _enable_kv2_k8s_auth)
  [ "${#calls[@]}" -eq "${#expected[@]}" ]
  for i in "${!expected[@]}"; do
    [ "${calls[$i]}" = "${expected[$i]}" ]
  done
}
