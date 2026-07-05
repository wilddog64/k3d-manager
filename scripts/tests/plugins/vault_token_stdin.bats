#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  SCRIPT_DIR="${BATS_TEST_DIRNAME}/../.."
  PLUGINS_DIR="$BATS_TEST_TMPDIR/plugins"
  mkdir -p "$PLUGINS_DIR"

  _err()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
  _warn() { printf 'WARN: %s\n' "$*" >&2; }
  _info() { printf 'INFO: %s\n' "$*" >&2; }
  _no_trace() { "$@"; }
  export -f _err _warn _info _no_trace

  touch "$PLUGINS_DIR/eso.sh"
  mkdir -p "$SCRIPT_DIR/lib"
  touch "$SCRIPT_DIR/lib/vault_pki.sh"

  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/plugins/vault.sh"

  _vault_container_name() { printf '%s\n' "vault"; }
  export VAULT_NS_DEFAULT="secrets"
  export VAULT_RELEASE_DEFAULT="vault"

  ARGV_LOG="$BATS_TEST_TMPDIR/argv.log"
  STDIN_LOG="$BATS_TEST_TMPDIR/stdin.log"
  : >"$ARGV_LOG"
  : >"$STDIN_LOG"
}

@test "_vault_exec keeps token out of kubectl argv and sends it on stdin" {
  __vault_exec_kubectl() {
    [[ "${1:-}" == "--exec-stdin" ]] && shift
    printf '%s\n' "$*" >"$ARGV_LOG"
    cat >"$STDIN_LOG"
    return 0
  }
  _VAULT_SESSION_TOKENS["secrets/vault"]="hvs.session"

  run _vault_exec "secrets" "vault kv get secret/x" "vault"
  [ "${status}" -eq 0 ]
  run cat "$ARGV_LOG"
  [[ "${output}" != *"VAULT_TOKEN=hvs.session"* ]]
  [[ "${output}" == *"read -r __VAULT_TOKEN"* ]]
  [[ "${output}" == *'export VAULT_TOKEN="$__VAULT_TOKEN"'* ]]
  run cat "$STDIN_LOG"
  [ "${output}" = "hvs.session" ]
}

@test "_vault_exec_stream --stdin multiplexes token line then payload" {
  __vault_exec_kubectl() {
    [[ "${1:-}" == "--exec-stdin" ]] && shift
    printf '%s\n' "$*" >"$ARGV_LOG"
    cat >"$STDIN_LOG"
    return 0
  }
  _VAULT_SESSION_TOKENS["secrets/vault"]="hvs.session"

  printf 'policy-body\n' | _vault_exec_stream --no-exit --stdin "secrets" "vault" \
    -- vault policy write eso-reader -
  run cat "$ARGV_LOG"
  [[ "${output}" != *"VAULT_TOKEN=hvs.session"* ]]
  [[ "${output}" == *"sh -c "* ]]
  [[ "${output}" == *'export VAULT_TOKEN="$__VAULT_TOKEN"'* ]]
  [[ "${output}" == *"vault policy write eso-reader -"* ]]
  run cat "$STDIN_LOG"
  [ "${lines[0]}" = "hvs.session" ]
  [ "${lines[1]}" = "policy-body" ]
}

@test "_vault_exec_stream session branch without --stdin sends only token line" {
  __vault_exec_kubectl() {
    [[ "${1:-}" == "--exec-stdin" ]] && shift
    printf '%s\n' "$*" >"$ARGV_LOG"
    cat >"$STDIN_LOG"
    return 0
  }
  _VAULT_SESSION_TOKENS["secrets/vault"]="hvs.session"

  _vault_exec_stream --no-exit "secrets" "vault" -- vault write auth/kubernetes/role/r x=y
  run cat "$ARGV_LOG"
  [[ "${output}" != *"VAULT_TOKEN=hvs.session"* ]]
  [[ "${output}" == *'export VAULT_TOKEN="$__VAULT_TOKEN"'* ]]
  [[ "${output}" == *"vault write auth/kubernetes/role/r x=y"* ]]
  run cat "$STDIN_LOG"
  [ "${output}" = "hvs.session" ]
}

@test "__vault_exec_kubectl --exec-stdin replays stdin across a retry" {
  ATTEMPT_FILE="$BATS_TEST_TMPDIR/attempts"
  printf '0' >"$ATTEMPT_FILE"
  _kubectl() {
    local seen
    seen=$(cat)
    printf '%s' "$seen" >>"$STDIN_LOG"
    local n
    n=$(cat "$ATTEMPT_FILE")
    if [[ "$n" == "0" ]]; then
      printf '1' >"$ATTEMPT_FILE"
      printf 'Error from server: container not found'
      return 1
    fi
    printf 'ok'
    return 0
  }

  run __vault_exec_kubectl --exec-stdin 0 "secrets" "vault" <<<"payload-line"
  [ "${status}" -eq 0 ]
  [ "${output}" = "ok" ]
  run cat "$STDIN_LOG"
  [ "${output}" = "payload-linepayload-line" ]
}
