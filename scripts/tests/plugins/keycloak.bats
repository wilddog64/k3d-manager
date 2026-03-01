#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/keycloak.sh"
}

@test "deploy_keycloak --help shows usage" {
  run deploy_keycloak --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: deploy_keycloak"* ]]
}

@test "deploy_keycloak skips when CLUSTER_ROLE=app" {
  CLUSTER_ROLE=app run deploy_keycloak
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLUSTER_ROLE=app"* ]]
}

@test "KEYCLOAK_NAMESPACE defaults to identity" {
  [ "$KEYCLOAK_NAMESPACE" = "identity" ]
}

@test "KEYCLOAK_HELM_RELEASE defaults to keycloak" {
  [ "$KEYCLOAK_HELM_RELEASE" = "keycloak" ]
}

@test "deploy_keycloak rejects unknown option" {
  run deploy_keycloak --unknown-flag
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown option"* ]]
}

@test "_keycloak_seed_vault_admin_secret function exists" {
  declare -F _keycloak_seed_vault_admin_secret >/dev/null
}
