#!/usr/bin/env bats
# shellcheck shell=bash

setup_cred_drift() {
  cat <<'EOF'
    SCRIPT_DIR="$(pwd)/scripts"
    source scripts/lib/system.sh
    source scripts/lib/core.sh
    source scripts/plugins/shopping_cart.sh
    calls="${BATS_TEST_TMPDIR}/calls"
    : > "$calls"
    kubectl() {
      printf '%s\n' "$*" >> "$calls"
      local args=("$@") arg key pod sts i
      if [[ "$*" == *" get pod "* ]]; then
        return 0
      fi
      if [[ "$*" == *" get secret "* ]]; then
        for arg in "${args[@]}"; do
          if [[ "$arg" == jsonpath=* ]]; then
            key="${arg##*.data.}"
            key="${key%}}"
            if [[ "$key" == "password" ]]; then
              printf '%s' 'c2VjcmV0LXZhbHVl'
            else
              printf '%s' 'cm1x'
            fi
          fi
        done
        return 0
      fi
      if [[ "$*" == *" exec -i "* ]]; then
        for ((i = 0; i < ${#args[@]} - 1; i++)); do
          if [[ "${args[i]}" == "-i" ]]; then
            pod="${args[i + 1]}"
          fi
        done
        cat >/dev/null
        if [[ "$*" == *"ALTER USER"* || "$*" == *"change_password"* ]]; then
          : > "${BATS_TEST_TMPDIR}/fixed-${pod}"
          return 0
        fi
        if [[ "$*" == *"cat >/dev/null; exit 0"* ]]; then
          return 0
        fi
        if [[ " ${TEST_DRIFT_PODS:-} " == *" ${pod} "* ]]; then
          if [[ -e "${BATS_TEST_TMPDIR}/fixed-${pod}" ]]; then
            return 0
          fi
          return 1
        fi
        return 0
      fi
      if [[ "$*" == *" rollout restart statefulset/"* ]]; then
        sts="${args[*]}"
        sts="${sts##*statefulset/}"
        sts="${sts%% *}"
        : > "${BATS_TEST_TMPDIR}/fixed-${sts}-0"
        return 0
      fi
      return 0
    }
EOF
}

@test "credential drift: no drift matches all stores in check mode" {
  run bash -c "$(setup_cred_drift); shopping_cart_credential_drift --context test-context; cat \"\$calls\""
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c ': MATCH')" -eq 6 ]
  [ "$(printf '%s\n' "$output" | grep -c 'rollout')" -eq 0 ]
}

@test "credential drift: postgres drift is reported in check mode" {
  run bash -c "TEST_DRIFT_PODS=postgresql-orders-0 $(setup_cred_drift); shopping_cart_credential_drift --context test-context; cat \"\$calls\""
  [ "$status" -eq 1 ]
  [[ "$output" == *"postgres-orders: DRIFT"* ]]
  [ "$(printf '%s\n' "$output" | grep -c 'ALTER USER')" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'rollout')" -eq 0 ]
}

@test "credential drift: postgres apply fixes and restarts only its consumer" {
  run bash -c "TEST_DRIFT_PODS=postgresql-orders-0 $(setup_cred_drift); shopping_cart_credential_drift --context test-context --apply; cat \"\$calls\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"postgres-orders: FIXED"* ]]
  [[ "$output" == *"exec -i postgresql-orders-0"*ALTER\ USER* ]]
  [[ "$output" == *"rollout restart deployment/order-service"* ]]
  [ "$(printf '%s\n' "$output" | grep -c 'deployment/basket-service')" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'deployment/payment-service')" -eq 0 ]
}

@test "credential drift: rabbitmq apply restarts each consumer once" {
  run bash -c "TEST_DRIFT_PODS=rabbitmq-0 $(setup_cred_drift); shopping_cart_credential_drift --context test-context --apply; cat \"\$calls\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"change_password"*rmq* ]]
  [ "$(printf '%s\n' "$output" | grep -c 'rollout restart deployment/order-service')" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c 'rollout restart deployment/product-catalog')" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c 'rollout restart deployment/payment-service')" -eq 1 ]
}

@test "credential drift: redis apply restarts the store and basket consumer" {
  run bash -c "TEST_DRIFT_PODS=redis-cart-0 $(setup_cred_drift); shopping_cart_credential_drift --context test-context --apply; cat \"\$calls\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"rollout restart statefulset/redis-cart"* ]]
  [[ "$output" == *"rollout restart deployment/basket-service"* ]]
}

@test "credential drift: apply keeps secret values out of kubectl calls" {
  run bash -c "TEST_DRIFT_PODS='postgresql-orders-0 postgresql-products-0 postgresql-payment-0 rabbitmq-0 redis-cart-0 redis-orders-cache-0' $(setup_cred_drift); shopping_cart_credential_drift --context test-context --apply; cat \"\$calls\""
  [ "$status" -eq 0 ]
  run grep -c 'c2VjcmV0LXZhbHVl' <<<"$output"
  [ "$output" = "0" ]
  run grep -c 'secret-value' <<<"$output"
  [ "$output" = "0" ]
}

@test "credential drift: context is required" {
  run bash -c 'SCRIPT_DIR="$(pwd)/scripts"; source scripts/lib/system.sh; source scripts/lib/core.sh; source scripts/plugins/shopping_cart.sh; _err() { printf "%s\n" "$*" >&2; return 0; }; shopping_cart_credential_drift'
  [ "$status" -eq 2 ]
}
