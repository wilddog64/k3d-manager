#!/usr/bin/env bats

setup() {
  CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
  : >"$CURL_LOG"

  _info() { printf '%s\n' "$*" >&2; }
  _warn() { printf '%s\n' "$*" >&2; }
  _err() { printf '%s\n' "$*" >&2; return 1; }
  _acg_fail() { printf '%s\n' "$*" >&2; return 1; }
  export -f _info _warn _err _acg_fail

  curl() {
    printf '%s\n' "$*" >>"$CURL_LOG"
    local url="${*: -1}"
    local path="${url#*/v1/secret/data/}"

    if [[ "$*" == *"-X POST"* ]]; then
      return 0
    fi

    case "$path" in
      redis/cart)
        [[ "${TEST_REDIS_CART_EXISTS:-0}" == "1" ]] || return 1
        printf '{"data":{"data":{"password":"cart-existing"}}}\n'
        ;;
      redis/orders-cache)
        [[ "${TEST_REDIS_ORDERS_EXISTS:-0}" == "1" ]] || return 1
        printf '{"data":{"data":{"password":"orders-existing"}}}\n'
        ;;
      rabbitmq/default)
        [[ "${TEST_RABBITMQ_EXISTS:-0}" == "1" ]] || return 1
        printf '{"data":{"data":{"password":"rabbit-existing"}}}\n'
        ;;
      postgres/orders)
        printf '{"data":{"data":{"password":"pg-orders"}}}\n'
        ;;
      postgres/products)
        printf '{"data":{"data":{"password":"pg-products"}}}\n'
        ;;
      postgres/payment)
        printf '{"data":{"data":{"password":"pg-payment"}}}\n'
        ;;
      minio/credentials)
        printf '{"data":{"data":{"root-user":"minioadmin","root-password":"minio-pass"}}}\n'
        ;;
      ldap/admin)
        printf '{"data":{"data":{"admin_password":"ldap-admin","readonly_password":"ldap-readonly"}}}\n'
        ;;
      keycloak/admin)
        printf '{"data":{"data":{"admin_password":"kc-admin","db_password":"kc-db"}}}\n'
        ;;
      keycloak/clients)
        printf '{"data":{"data":{"argocd_client_secret":"argo","order_service_client_secret":"order","product_catalog_client_secret":"product","grafana_client_secret":"grafana"}}}\n'
        ;;
      *)
        return 1
        ;;
    esac
  }

  jq() {
    local input
    input=$(cat)
    if [[ "$1" == "-r" ]]; then
      case "$input" in
        *'"password":"cart-existing"'*) printf 'cart-existing\n' ;;
        *'"password":"orders-existing"'*) printf 'orders-existing\n' ;;
        *'"password":"rabbit-existing"'*) printf 'rabbit-existing\n' ;;
        *'"password":"pg-orders"'*) printf 'pg-orders\n' ;;
        *'"password":"pg-products"'*) printf 'pg-products\n' ;;
        *'"password":"pg-payment"'*) printf 'pg-payment\n' ;;
        *'"root-user":"minioadmin"'*)
          [[ "${*: -1}" == *"root-user"* ]] && printf 'minioadmin\n' || printf 'minio-pass\n'
          ;;
        *'"admin_password":"ldap-admin"'*)
          [[ "${*: -1}" == *"admin_password"* ]] && printf 'ldap-admin\n' || printf 'ldap-readonly\n'
          ;;
        *'"admin_password":"kc-admin"'*)
          [[ "${*: -1}" == *"admin_password"* ]] && printf 'kc-admin\n' || printf 'kc-db\n'
          ;;
        *'"argocd_client_secret":"argo"'*)
          case "${*: -1}" in
            *argocd_client_secret*) printf 'argo\n' ;;
            *order_service_client_secret*) printf 'order\n' ;;
            *product_catalog_client_secret*) printf 'product\n' ;;
            *) printf 'grafana\n' ;;
          esac
          ;;
      esac
      return 0
    fi
    printf '%s\n' "$input"
  }

  openssl() {
    printf 'generated-secret\n'
  }

  export -f curl jq openssl

  # shellcheck disable=SC1090
  source "${BATS_TEST_DIRNAME}/../../plugins/shopping_cart.sh"
}

@test "reuses existing redis and rabbitmq secrets without PUT for those paths" {
  export _vault_local_port="8200"
  export _vault_root_token="root-token"
  export TEST_REDIS_CART_EXISTS="1"
  export TEST_REDIS_ORDERS_EXISTS="1"
  export TEST_RABBITMQ_EXISTS="1"

  run shopping_cart_seed_sandbox_vault_kv
  [ "$status" -eq 0 ]
  ! grep -q 'POST .*redis/cart$' "$CURL_LOG"
  ! grep -q 'POST .*redis/orders-cache$' "$CURL_LOG"
  ! grep -q 'POST .*rabbitmq/default$' "$CURL_LOG"
}

@test "puts redis and rabbitmq secrets when absent" {
  export _vault_local_port="8200"
  export _vault_root_token="root-token"
  export TEST_REDIS_CART_EXISTS="0"
  export TEST_REDIS_ORDERS_EXISTS="0"
  export TEST_RABBITMQ_EXISTS="0"

  run shopping_cart_seed_sandbox_vault_kv
  [ "$status" -eq 0 ]
  grep -q 'POST .*redis/cart$' "$CURL_LOG"
  grep -q 'POST .*redis/orders-cache$' "$CURL_LOG"
  grep -q 'POST .*rabbitmq/default$' "$CURL_LOG"
}

@test "seed helpers honor SEED_VAULT_ADDR instead of localhost port" {
  export _vault_local_port="8200"
  export _vault_root_token="root-token"
  export SEED_VAULT_ADDR="http://example:9999"
  export TEST_REDIS_CART_EXISTS="0"
  export TEST_REDIS_ORDERS_EXISTS="0"
  export TEST_RABBITMQ_EXISTS="0"

  run shopping_cart_seed_sandbox_vault_kv
  [ "$status" -eq 0 ]
  grep -q 'http://example:9999/v1/secret/data/redis/cart' "$CURL_LOG"
  ! grep -q 'http://localhost:8200/v1/secret/data/redis/cart' "$CURL_LOG"
}
