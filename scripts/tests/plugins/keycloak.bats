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

@test "_keycloak_reconcile_realm_client function exists" {
  declare -F _keycloak_reconcile_realm_client >/dev/null
}

@test "_keycloak_reconcile_realm_client updates argocd redirect URIs" {
  local realm_json="$BATS_TEST_TMPDIR/realm-shopping-cart.json"
  cp "${BATS_TEST_DIRNAME}/../../../../shopping-carts/shopping-cart-infra/identity/keycloak/realm-shopping-cart.json" "$realm_json"

  local curl_log="$BATS_TEST_TMPDIR/curl.log"
  local put_body="$BATS_TEST_TMPDIR/put-body.json"
  : > "$curl_log"
  : > "$put_body"

  _curl() {
    printf '%s\n' "$*" >> "$curl_log"
    local -a args=("$@")
    local body=""
    local i
    for ((i=0; i<${#args[@]}; i++)); do
      if [[ "${args[i]}" == "--data-binary" && $((i + 1)) -lt ${#args[@]} ]]; then
        body="${args[i+1]}"
        break
      fi
    done

    case "$*" in
      *"/admin/realms/shopping-cart/clients?clientId=argocd"*)
        printf '[{"id":"abc123","clientId":"argocd"}]'
        return 0
        ;;
      *"/admin/realms/shopping-cart/clients/abc123"*)
        printf '%s' "$body" > "$put_body"
        return 0
        ;;
    esac

    return 1
  }
  export -f _curl

  run _keycloak_reconcile_realm_client "http://localhost:18080" "fake-token" "shopping-cart" "argocd" "$realm_json"
  [ "$status" -eq 0 ]
  grep -q "/admin/realms/shopping-cart/clients?clientId=argocd" "$curl_log"
  grep -q "/admin/realms/shopping-cart/clients/abc123" "$curl_log"

  local put_payload
  put_payload=$(cat "$put_body")
  [[ "$put_payload" == *"https://argocd.shopping-cart.local/*"* ]]
  [[ "$put_payload" == *"http://localhost:8080/*"* ]]
}

@test "_keycloak_remove_client_attribute deletes stale pkce attribute rows" {
  local exec_log="$BATS_TEST_TMPDIR/exec.log"
  : > "$exec_log"

  _kubectl() {
    printf '%s\n' "$*" >> "$exec_log"
    case "$*" in
      *"get secret keycloak-secrets"*)
        printf 'ZHVtbXktZGItcGFzcw=='
        return 0
        ;;
      *"get pod -l app.kubernetes.io/name=postgres-keycloak"*)
        printf 'postgres-keycloak-0'
        return 0
        ;;
      *"exec -i postgres-keycloak-0 -- bash"*)
        return 0
        ;;
    esac
    return 1
  }
  export -f _kubectl

  run _keycloak_remove_client_attribute "shopping-cart" "argocd" "pkce.code.challenge.method" "identity"
  [ "$status" -eq 0 ]
  grep -q "postgres-keycloak-0" "$exec_log"
}

@test "KEYCLOAK_CONFIG_CLI_ENABLED defaults to false" {
  [ "$KEYCLOAK_CONFIG_CLI_ENABLED" = "false" ]
}

@test "test_keycloak function exists" {
  declare -F test_keycloak >/dev/null
}
