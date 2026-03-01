#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
}

@test "deploy_argocd --help shows usage" {
  run deploy_argocd --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: deploy_argocd"* ]]
}

@test "deploy_argocd skips when CLUSTER_ROLE=app" {
  CLUSTER_ROLE=app run deploy_argocd
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLUSTER_ROLE=app"* ]]
}

@test "deploy_argocd_bootstrap --help shows usage" {
  run deploy_argocd_bootstrap -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: deploy_argocd_bootstrap"* ]]
}

@test "deploy_argocd_bootstrap no-ops when skipping all resources" {
  : > "$KUBECTL_LOG"
  run deploy_argocd_bootstrap --skip-applicationsets --skip-appproject
  [ "$status" -eq 0 ]
  read_lines "$KUBECTL_LOG" calls
  [ "${calls[0]}" = "get ns cicd" ]
  [ "${calls[1]}" = "-n cicd get deployment argocd-server" ]
}

@test "_argocd_deploy_appproject fails when template missing" {
  local original_config="$ARGOCD_CONFIG_DIR"
  ARGOCD_CONFIG_DIR="$BATS_TEST_TMPDIR/argocd-empty"
  mkdir -p "$ARGOCD_CONFIG_DIR/projects"
  trap 'ARGOCD_CONFIG_DIR="$original_config"' RETURN
  run _argocd_deploy_appproject
  [ "$status" -ne 0 ]
  [[ "$output" == *"AppProject file not found"* ]]
}

@test "ARGOCD_NAMESPACE defaults to cicd" {
  [ "$ARGOCD_NAMESPACE" = "cicd" ]
}
