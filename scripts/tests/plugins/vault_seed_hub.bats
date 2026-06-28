#!/usr/bin/env bats

setup() {
  SCRIPT_DIR="${BATS_TEST_DIRNAME}/../.."
  PLUGINS_DIR="$BATS_TEST_TMPDIR/plugins"
  mkdir -p "$PLUGINS_DIR"

  _err() {
    printf '%s\n' "$*" >&2
    return 1
  }
  _warn() { printf '%s\n' "$*" >&2; }
  _info() { printf '%s\n' "$*" >&2; }
  export -f _err _warn _info

  touch "$PLUGINS_DIR/eso.sh"
  mkdir -p "$SCRIPT_DIR/lib"
  touch "$SCRIPT_DIR/lib/vault_pki.sh"

  _kubectl() {
    if [[ "$1" == "config" && "$2" == "get-contexts" && "$3" == "-o" && "$4" == "name" ]]; then
      printf '%s\n' "${TEST_CONTEXTS:-k3d-k3d-cluster}"
      return 0
    fi
    return 0
  }
  export -f _kubectl

  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/plugins/vault.sh"
}

@test "vault_seed_hub_into_context requires an app cluster kube-context" {
  run vault_seed_hub_into_context
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires an app cluster kube-context"* ]]
}

@test "vault_seed_hub_into_context rejects unknown kube-contexts" {
  export TEST_CONTEXTS=$'k3d-k3d-cluster\nubuntu-hostinger'
  run vault_seed_hub_into_context does-not-exist
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found in kubeconfig"* ]]
}

@test "vault_seed_hub_into_context canonical key list contains exactly 13 keys" {
  run sed -n '/local _keys=(/,/)/p' "${SCRIPT_DIR}/plugins/vault.sh"
  [ "$status" -eq 0 ]
  actual_keys=$(printf '%s\n' "$output" | awk '
    /local _keys=\(/ { next }
    /^[[:space:]]*\)/ { exit }
    {
      for (i = 1; i <= NF; i++) {
        print $i
      }
    }
  ')
  expected_keys=$'redis/cart\nredis/orders-cache\npostgres/orders\npostgres/products\npostgres/payment\npayment/encryption\npayment/stripe\npayment/paypal\nrabbitmq/default\nminio/credentials\nldap/admin\nkeycloak/admin\nkeycloak/clients'
  [ "$actual_keys" = "$expected_keys" ]
}
