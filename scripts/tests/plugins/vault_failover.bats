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

@test "_vault_hub_fallback_profile maps hostinger -> laptop" {
  run _vault_hub_fallback_profile hostinger
  [ "$status" -eq 0 ]
  [ "$output" = "laptop" ]
}

@test "_vault_hub_fallback_profile maps laptop (and default) -> hostinger" {
  run _vault_hub_fallback_profile laptop
  [ "$output" = "hostinger" ]
  run _vault_hub_fallback_profile
  [ "$output" = "hostinger" ]
}

@test "_vault_health_status_ok accepts 200/429/472/473, rejects others" {
  for code in 200 429 472 473; do
    run _vault_health_status_ok "$code"
    [ "$status" -eq 0 ]
  done
  for code in 000 404 500 503 ""; do
    run _vault_health_status_ok "$code"
    [ "$status" -ne 0 ]
  done
}

@test "vault_failover_hub_into_context requires an app cluster kube-context" {
  run vault_failover_hub_into_context
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires an app cluster kube-context"* ]]
}

@test "vault_failover_hub_into_context rejects unknown kube-contexts" {
  export TEST_CONTEXTS=$'k3d-k3d-cluster\nubuntu-hostinger'
  run vault_failover_hub_into_context does-not-exist
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found in kubeconfig"* ]]
}

@test "vault_failover_hub_into_context rejects unknown flags" {
  run vault_failover_hub_into_context ubuntu-hostinger --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown flag"* ]]
}
