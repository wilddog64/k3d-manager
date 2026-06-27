#!/usr/bin/env bats

setup() {
  # shellcheck disable=SC1090
  source "${BATS_TEST_DIRNAME}/../../plugins/shopping_cart.sh"
}

@test "token mode emits tokenSecretRef block" {
  run _shopping_cart_css_auth_block token
  [ "$status" -eq 0 ]
  [[ "$output" == *"tokenSecretRef:"* ]]
  [[ "$output" == *"name: vault-token"* ]]
  [[ "$output" != *"kubernetes:"* ]]
}

@test "default (no arg) is token mode" {
  run _shopping_cart_css_auth_block
  [ "$status" -eq 0 ]
  [[ "$output" == *"tokenSecretRef:"* ]]
}

@test "kubernetes mode emits kubernetes auth block with defaults" {
  unset APP_K8S_AUTH_MOUNT APP_ESO_VAULT_ROLE APP_ESO_SA_NAME APP_ESO_SA_NS
  run _shopping_cart_css_auth_block kubernetes
  [ "$status" -eq 0 ]
  [[ "$output" == *"kubernetes:"* ]]
  [[ "$output" == *"mountPath: \"kubernetes-app\""* ]]
  [[ "$output" == *"role: \"eso-app-cluster\""* ]]
  [[ "$output" == *"name: \"external-secrets\""* ]]
  [[ "$output" != *"tokenSecretRef:"* ]]
}

@test "kubernetes mode honors mount/role overrides" {
  export APP_K8S_AUTH_MOUNT="kubernetes-hostinger" APP_ESO_VAULT_ROLE="eso-hostinger"
  run _shopping_cart_css_auth_block kubernetes
  [ "$status" -eq 0 ]
  [[ "$output" == *"mountPath: \"kubernetes-hostinger\""* ]]
  [[ "$output" == *"role: \"eso-hostinger\""* ]]
}
