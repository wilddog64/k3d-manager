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
  _err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
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

_init_stubs() {
  _vault_wait_api() { return 0; }
  _vault_container_name() { printf 'vault\n'; }
  export VAULT_INIT_POD_FILE="$BATS_TEST_TMPDIR/pod-init" CALLS INIT_OK_ON
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/vault" <<'STUB'
#!/bin/sh
printf 'init\n' >> "$CALLS"
if [ "$(grep -c '^init$' "$CALLS")" -ge "${INIT_OK_ON:-99}" ]; then
  printf '{"unseal_keys_b64":["KEY"],"root_token":"TOKEN-SENTINEL"}\n'
  exit 0
fi
printf 'Error initializing: context canceled\n"root_token": "TOKEN-SENTINEL"\n' >&2
exit 2
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/vault"
  _kubectl() {
    case " $* " in
      *" exec "*)
        local script="${!#}"
        if [[ "$script" == "cat "*".json" ]] && [ "$(grep -c '^drop$' "$CALLS")" -lt "${JSON_DROPS:-0}" ]; then
          printf 'drop\n' >> "$CALLS"
          return 1
        fi
        if [[ "$script" == "rm -f "* && "$script" != *nohup* ]]; then
          printf 'cleanup\n' >> "$CALLS"
        fi
        PATH="$BATS_TEST_TMPDIR/bin:$PATH" sh -c "${script//sh -lc/sh -c}" ;;
      *jsonpath*) printf 'Running' ;;
    esac
  }
}

@test "vault init: never retries once Vault reports initialised" {
  _init_stubs
  _vault_is_initialized() { return 0; }
  run --separate-stderr _vault_operator_init secrets vault
  [ "$status" -ne 0 ]
  [ "$(grep -c '^init$' "$CALLS")" -eq 1 ]
  [[ "$stderr" == *"cannot be recovered"* ]]
  [[ "$stderr" == *"context canceled"* ]]
  [[ "$stderr" != *"SENTINEL"* ]]
}

@test "vault init: retries while Vault is still uninitialised" {
  _init_stubs
  _vault_is_initialized() { return 1; }
  INIT_OK_ON=2 run --separate-stderr _vault_operator_init secrets vault
  [ "$status" -eq 0 ]
  [ "$(grep -c '^init$' "$CALLS")" -eq 2 ]
  grep -q TOKEN-SENTINEL "$output"
  rm -f "$output"
}

@test "vault init: gives up after the attempt limit" {
  _init_stubs
  _vault_is_initialized() { return 1; }
  VAULT_INIT_ATTEMPTS=3 run --separate-stderr _vault_operator_init secrets vault
  [ "$status" -ne 0 ]
  [ "$(grep -c '^init$' "$CALLS")" -eq 3 ]
  [[ "$stderr" == *"failed to execute vault operator init"* ]]
}

@test "vault is_initialized: reads the initialized field" {
  _vault_exec() { printf '{"initialized": true, "sealed": true}\n'; }
  run _vault_is_initialized secrets vault
  [ "$status" -eq 0 ]
  _vault_exec() { printf '{"initialized": false, "sealed": true}\n'; }
  run _vault_is_initialized secrets vault
  [ "$status" -eq 1 ]
}

@test "vault init: a dropped read is retried and the keys come back" {
  _init_stubs
  _vault_is_initialized() { return 0; }
  INIT_OK_ON=1 JSON_DROPS=2 run --separate-stderr _vault_operator_init secrets vault
  [ "$status" -eq 0 ]
  [ "$(grep -c '^init$' "$CALLS")" -eq 1 ]
  grep -q unseal_keys_b64 "$output"
  [ "$(grep -c '^cleanup$' "$CALLS")" -eq 1 ]
  [ ! -e "$VAULT_INIT_POD_FILE.json" ]
  rm -f "$output"
}

@test "vault init: keys left in the pod when they cannot be read back" {
  _init_stubs
  _vault_is_initialized() { return 0; }
  INIT_OK_ON=1 JSON_DROPS=99 run --separate-stderr _vault_operator_init secrets vault
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"keys are still in vault-0"* ]]
  [[ "$stderr" != *"cannot be recovered"* ]]
  [[ "$stderr" != *"SENTINEL"* ]]
  [ "$(grep -c '^cleanup$' "$CALLS")" -eq 0 ]
  grep -q unseal_keys_b64 "$VAULT_INIT_POD_FILE.json"
}

@test "vault init: stops when init never finishes" {
  _init_stubs
  _vault_pod_sh() { return 1; }
  _vault_is_initialized() { return 1; }
  VAULT_INIT_WAIT_S=0 VAULT_INIT_ATTEMPTS=1 run --separate-stderr _vault_operator_init secrets vault
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"did not finish within 0s"* ]]
}
