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

@test "smoke admin Secret falls back to keycloak-secrets" {
  _kubectl() {
    case "$*" in
      *"get secret keycloak-admin-secret"*) return 1 ;;
      *"get secret keycloak-secrets"*) return 0 ;;
    esac
    return 1
  }
  run _keycloak_smoke_admin_secret_name identity keycloak-admin-secret
  [ "${status}" -eq 0 ]
  [ "${output}" = "keycloak-secrets" ]
}

@test "smoke admin Secret keeps preferred Secret when both exist" {
  _kubectl() { return 0; }
  run _keycloak_smoke_admin_secret_name identity keycloak-admin-secret
  [ "${status}" -eq 0 ]
  [ "${output}" = "keycloak-admin-secret" ]
}

@test "smoke admin Secret keeps preferred Secret when neither exists" {
  _kubectl() { return 1; }
  run _keycloak_smoke_admin_secret_name identity keycloak-admin-secret
  [ "${status}" -eq 0 ]
  [ "${output}" = "keycloak-admin-secret" ]
}

@test "_keycloak_reconcile_realm_client updates argocd redirect URIs" {
  local realm_json="$BATS_TEST_TMPDIR/realm-shopping-cart.json"
  local realm_src
  realm_src="${BATS_TEST_DIRNAME}/../../../../shopping-carts/shopping-cart-infra/identity/keycloak/realm-shopping-cart.json"
  if [[ ! -r "$realm_src" ]]; then
    skip "shopping-cart-infra realm fixture not reachable: ${realm_src}"
  fi
  cp "$realm_src" "$realm_json"

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

@test "smoke admin token supports the deployed password-only admin Secret" {
  run grep -F 'KEYCLOAK_ADMIN_PASSWORD_KEY:-password' "$BATS_TEST_DIRNAME/../../plugins/keycloak.sh"
  [ "$status" -eq 0 ]
  run grep -F 'admin_user="${KEYCLOAK_ADMIN_USERNAME:-admin}"' "$BATS_TEST_DIRNAME/../../plugins/keycloak.sh"
  [ "$status" -eq 0 ]
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

setup_smoke_stubs() {
  export SMOKE_VAULT_PASSWORD="${1:-}"
  export SMOKE_LEGACY_PASSWORD="${2:-}"
  export SMOKE_OWNER_JSON="${3:-}"
  [[ -n "$SMOKE_OWNER_JSON" ]] || export SMOKE_OWNER_JSON='{}'
  export SMOKE_VAULT_PUT_RC="${4:-0}"
  export SMOKE_EXTERNALSECRET_EXISTS="${5:-0}"
  export SMOKE_KUBECTL_LOG="$BATS_TEST_TMPDIR/smoke-kubectl.log"
  : > "$SMOKE_KUBECTL_LOG"

  _kubectl() {
    local args="$*" input=""
    if [[ "$args" == *"exec -i vault-0"* ]]; then
      input=$(cat)
    fi
    printf 'ARGV\t%s\n' "${args//$'\n'/ }" >> "$SMOKE_KUBECTL_LOG"
    printf 'STDIN\t%s\n' "${input//$'\n'/ }" >> "$SMOKE_KUBECTL_LOG"
    case "$args" in
      *"get secret vault-root"*)
        printf 'cm9vdC10b2tlbg=='
        return 0
        ;;
      *"exec -i vault-0"*"vault kv get"*)
        printf '%s' "$SMOKE_VAULT_PASSWORD"
        [[ -n "$SMOKE_VAULT_PASSWORD" ]]
        return $?
        ;;
      *"exec -i vault-0"*"vault kv put"*)
        printf 'PUT_INPUT\t%s\n' "$input" >> "$SMOKE_KUBECTL_LOG"
        return "$SMOKE_VAULT_PUT_RC"
        ;;
      *"get secret k3dm-smoke-user"*"jsonpath"*)
        [[ -n "$SMOKE_LEGACY_PASSWORD" ]] || return 1
        printf '%s' "$SMOKE_LEGACY_PASSWORD" | base64
        return 0
        ;;
      *"get secret k3dm-smoke-user"*"-o json"*)
        printf '%s' "$SMOKE_OWNER_JSON"
        return 0
        ;;
      *"get externalsecret k3dm-smoke-user"*)
        [[ "$SMOKE_EXTERNALSECRET_EXISTS" == 1 ]]
        return $?
        ;;
      *"get secret openldap-admin"*)
        printf 'bGRhcC1wYXNz'
        return 0
        ;;
      *"delete secret k3dm-smoke-user"*)
        return 0
        ;;
    esac
    return 0
  }
  _curl() { return 0; }
  _keycloak_smoke_admin_token() { printf 'admin-token'; }
  _keycloak_smoke_ensure_client() { return 0; }
  _keycloak_smoke_ensure_user() { printf 'user-uuid'; }
  _keycloak_smoke_set_password() { printf '%s' "$5" > "$BATS_TEST_TMPDIR/selected-password"; return 0; }
  _keycloak_smoke_ensure_realm() { return 0; }
  _keycloak_smoke_ensure_ldap_component() { return 0; }
  _keycloak_smoke_ensure_ldap_user() { printf '%s' "$8" > "$BATS_TEST_TMPDIR/selected-password"; return 0; }
  openssl() { printf 'generated-password'; }
  export -f _kubectl _curl _keycloak_smoke_admin_token _keycloak_smoke_ensure_client
  export -f _keycloak_smoke_ensure_user _keycloak_smoke_set_password openssl
  export -f _keycloak_smoke_ensure_realm _keycloak_smoke_ensure_ldap_component
  export -f _keycloak_smoke_ensure_ldap_user
}

@test "smoke seed prefers Vault password and does not run openssl" {
  setup_smoke_stubs vault-password
  run keycloak_seed_smoke_user
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/selected-password")" = "vault-password" ]
  run grep -q 'generated-password' "$SMOKE_KUBECTL_LOG"
  [ "$status" -ne 0 ]
  run grep -q 'ARGV.*vault-password' "$SMOKE_KUBECTL_LOG"
  [ "$status" -ne 0 ]
}

@test "smoke Vault preseed writes absent entry with four fields and a 48-hex password" {
  setup_smoke_stubs
  openssl() { printf '0123456789abcdef0123456789abcdef0123456789abcdef'; }
  run keycloak_smoke_vault_preseed
  [ "$status" -eq 0 ]
  grep -q '"username": "k3dm-smoke"' "$SMOKE_KUBECTL_LOG"
  grep -q '"password": "0123456789abcdef0123456789abcdef0123456789abcdef"' "$SMOKE_KUBECTL_LOG"
  grep -q '"realm": "shopping-cart"' "$SMOKE_KUBECTL_LOG"
  grep -q '"client": "k3dm-smoke"' "$SMOKE_KUBECTL_LOG"
  run grep -q 'ARGV.*0123456789abcdef' "$SMOKE_KUBECTL_LOG"
  [ "$status" -ne 0 ]
  [[ "$output" != *0123456789abcdef* ]]
}

@test "smoke Vault preseed leaves present entry untouched" {
  setup_smoke_stubs present-password
  _info() { printf '%s\n' "$*" >> "$SMOKE_KUBECTL_LOG"; }
  run keycloak_smoke_vault_preseed
  [ "$status" -eq 0 ]
  run grep -q 'vault kv put' "$SMOKE_KUBECTL_LOG"
  [ "$status" -ne 0 ]
  grep -q 'smoke-user Vault entry present' "$SMOKE_KUBECTL_LOG"
}

@test "smoke Vault preseed forces ESO refresh after a successful put" {
  setup_smoke_stubs '' '' '{}' 0 1
  run keycloak_smoke_vault_preseed
  [ "$status" -eq 0 ]
  local put_line annotate_line
  put_line=$(grep -n 'vault kv put' "$SMOKE_KUBECTL_LOG" | cut -d: -f1)
  annotate_line=$(grep -n 'annotate externalsecret k3dm-smoke-user force-sync=' "$SMOKE_KUBECTL_LOG" | cut -d: -f1)
  [ -n "$put_line" ]
  [ -n "$annotate_line" ]
  [ "$put_line" -lt "$annotate_line" ]
}

@test "smoke Vault preseed skips ESO refresh when ExternalSecret is absent" {
  setup_smoke_stubs
  run keycloak_smoke_vault_preseed
  [ "$status" -eq 0 ]
  run grep -q 'annotate externalsecret k3dm-smoke-user' "$SMOKE_KUBECTL_LOG"
  [ "$status" -ne 0 ]
}

@test "smoke Vault preseed skips ESO refresh when the put fails" {
  setup_smoke_stubs '' '' '{}' 1 1
  run keycloak_smoke_vault_preseed
  [ "$status" -ne 0 ]
  run grep -q 'annotate externalsecret k3dm-smoke-user' "$SMOKE_KUBECTL_LOG"
  [ "$status" -ne 0 ]
}

@test "smoke seed reuses legacy password and writes all Vault fields" {
  setup_smoke_stubs '' legacy-password
  run keycloak_seed_smoke_user
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/selected-password")" = "legacy-password" ]
  grep -q '"password": "legacy-password"' "$SMOKE_KUBECTL_LOG"
  grep -q 'vault kv get -mount=secret -field=password keycloak/smoke-user' "$SMOKE_KUBECTL_LOG"
  grep -q '"username": "k3dm-smoke"' "$SMOKE_KUBECTL_LOG"
  grep -q '"realm": "shopping-cart"' "$SMOKE_KUBECTL_LOG"
  grep -q '"client": "k3dm-smoke"' "$SMOKE_KUBECTL_LOG"
}

@test "smoke seed generates a password when Vault and legacy Secret are empty" {
  setup_smoke_stubs
  run keycloak_seed_smoke_user
  [ "$status" -eq 0 ]
  grep -q '"password": "generated-password"' "$SMOKE_KUBECTL_LOG"
}

@test "smoke seed and provision never create the smoke Secret" {
  setup_smoke_stubs
  run keycloak_seed_smoke_user
  [ "$status" -eq 0 ]
  run keycloak_provision_shopping_cart_realm
  [ "$status" -eq 0 ]
  run grep -q 'create secret generic k3dm-smoke-user' "$SMOKE_KUBECTL_LOG"
  [ "$status" -ne 0 ]
}

@test "smoke Vault hygiene keeps token and password out of kubectl argv" {
  setup_smoke_stubs secret-password
  run keycloak_seed_smoke_user
  [ "$status" -eq 0 ]
  run grep -q 'ARGV.*root-token' "$SMOKE_KUBECTL_LOG"
  [ "$status" -ne 0 ]
  run grep -q 'ARGV.*secret-password' "$SMOKE_KUBECTL_LOG"
  [ "$status" -ne 0 ]
  grep -q 'STDIN.*root-token' "$SMOKE_KUBECTL_LOG"
  grep -q '"password": "secret-password"' "$SMOKE_KUBECTL_LOG"
}

@test "smoke Vault write failure warns and returns zero" {
  setup_smoke_stubs '' '' '{}' 1
  run keycloak_seed_smoke_user
  [ "$status" -eq 0 ]
  [[ "$output" == *"secret/keycloak/smoke-user"* ]]
}

@test "smoke cleanup deletes an unowned legacy Secret" {
  setup_smoke_stubs '' '' '{}'
  run _keycloak_smoke_remove_unowned_secret identity k3dm-smoke-user
  [ "$status" -eq 0 ]
  grep -q 'delete secret k3dm-smoke-user' "$SMOKE_KUBECTL_LOG"
}

@test "smoke cleanup preserves an ESO-owned Secret" {
  setup_smoke_stubs '' '' '{"metadata":{"ownerReferences":[{"kind":"ExternalSecret"}]}}'
  run _keycloak_smoke_remove_unowned_secret identity k3dm-smoke-user
  [ "$status" -eq 0 ]
  run grep -q 'delete secret k3dm-smoke-user' "$SMOKE_KUBECTL_LOG"
  [ "$status" -ne 0 ]
}
