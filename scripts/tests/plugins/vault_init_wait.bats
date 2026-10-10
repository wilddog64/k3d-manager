#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  SCRIPT_DIR="${BATS_TEST_DIRNAME}/../.."
  PLUGINS_DIR="${SCRIPT_DIR}/plugins"
  source "${SCRIPT_DIR}/lib/core.sh"
  source "${BATS_TEST_DIRNAME}/../../plugins/vault.sh"
  CALLS="${BATS_TEST_TMPDIR}/calls"; : > "$CALLS"
  sleep() { :; }
  _info() { :; }
}

@test "vault init wait: returns once the API answers" {
  _vault_exec() { printf x >> "$CALLS"; [ "$(wc -c < "$CALLS" | tr -d ' ')" -ge 3 ]; }
  run _vault_wait_api secrets vault
  [ "$status" -eq 0 ]
  [ "$(wc -c < "$CALLS" | tr -d ' ')" -eq 3 ]
}

@test "vault init wait: gives up when the API never answers" {
  _vault_exec() { printf x >> "$CALLS"; return 1; }
  VAULT_API_WAIT_S=0 run _vault_wait_api secrets vault
  [ "$status" -eq 1 ]
}

@test "vault init error lines: shows errors, never key material" {
  printf '%s\n' 'Error initializing: Put "http://127.0.0.1:8200/v1/sys/init": EOF' \
    '"unseal_keys_b64": ["KEY-SENTINEL"]' '"root_token": "TOKEN-SENTINEL"' 'error: key SENTINEL in error' > "$BATS_TEST_TMPDIR/out"
  run _vault_init_error_lines "$BATS_TEST_TMPDIR/out"
  [[ "$output" == *"Error initializing"* ]]
  [[ "$output" != *"SENTINEL"* ]]
}
