#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# vault_k8s_auth_config.bats — offline tests for Vault Kubernetes auth config writers
# Specced in docs/bugs/2026-11-15-vault-pod-restart-invalidates-token-reviewer-jwt-eso-403.md
# Proves: M1, M2, N1, N2, N3 via E1 and E2.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  export REPO_ROOT
  export SCRIPT_DIR="${REPO_ROOT}/scripts"
  export PLUGINS_DIR="${BATS_TEST_TMPDIR}/plugins"
  mkdir -p "${PLUGINS_DIR}"
  touch "${PLUGINS_DIR}/eso.sh"

  export STREAM_LOG="${BATS_TEST_TMPDIR}/vault_exec_stream.log"
  export KUBECTL_ARGV_LOG="${BATS_TEST_TMPDIR}/kubectl_argv.log"
  export KUBECTL_STDIN_LOG="${BATS_TEST_TMPDIR}/kubectl_stdin.log"
  export TRAP_LOG="${BATS_TEST_TMPDIR}/trap.log"
  export XTRACE_LOG="${BATS_TEST_TMPDIR}/xtrace.log"

  : > "${STREAM_LOG}"
  : > "${KUBECTL_ARGV_LOG}"
  : > "${KUBECTL_STDIN_LOG}"
  : > "${TRAP_LOG}"
  : > "${XTRACE_LOG}"
}

# Helper to assert that a captured payload/argv for auth/kubernetes/config meets M1, N1, N2:
# - sets kubernetes_host="https://kubernetes.default.svc:443"
# - sets kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
# - contains no token_reviewer_jwt= (N1)
# - contains no disable_local_ca_jwt=true (N2)
assert_clean_k8s_auth_config() {
  local content="$1"
  local writer="${2:-writer}"

  if [[ "$content" != *"auth/kubernetes/config"* ]]; then
    printf 'FAIL: %s did not write to auth/kubernetes/config\n' "$writer" >&2
    return 1
  fi
  if [[ "$content" != *"kubernetes_host="* || "$content" != *"https://kubernetes.default.svc:443"* ]]; then
    printf 'FAIL: %s missing or incorrect kubernetes_host\n' "$writer" >&2
    return 1
  fi
  if [[ "$content" != *"kubernetes_ca_cert="* || "$content" != *"/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"* ]]; then
    printf 'FAIL: %s missing or incorrect kubernetes_ca_cert\n' "$writer" >&2
    return 1
  fi
  if [[ "$content" == *"token_reviewer_jwt="* ]]; then
    printf 'FAIL: %s contains token_reviewer_jwt=\n' "$writer" >&2
    return 1
  fi
  if [[ "$content" == *"disable_local_ca_jwt=true"* ]]; then
    printf 'FAIL: %s contains disable_local_ca_jwt=true\n' "$writer" >&2
    return 1
  fi
  return 0
}

@test "E1 positive control: assert helper flags a planted token_reviewer_jwt and disable_local_ca_jwt" {
  local planted_jwt="vault write auth/kubernetes/config token_reviewer_jwt=planted kubernetes_host=\"https://kubernetes.default.svc:443\" kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
  run assert_clean_k8s_auth_config "$planted_jwt" "planted-jwt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"contains token_reviewer_jwt="* ]]

  local planted_disable="vault write auth/kubernetes/config disable_local_ca_jwt=true kubernetes_host=\"https://kubernetes.default.svc:443\" kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
  run assert_clean_k8s_auth_config "$planted_disable" "planted-disable"
  [ "$status" -ne 0 ]
  [[ "$output" == *"contains disable_local_ca_jwt=true"* ]]

  local missing_host="vault write auth/kubernetes/config kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
  run assert_clean_k8s_auth_config "$missing_host" "missing-host"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing or incorrect kubernetes_host"* ]]

  local clean="vault write auth/kubernetes/config kubernetes_host=\"https://kubernetes.default.svc:443\" kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
  run assert_clean_k8s_auth_config "$clean" "clean"
  [ "$status" -eq 0 ]
}

@test "E1 [M1, N1, N2]: _vault_set_eso_reader writes auth config without token_reviewer_jwt or disable_local_ca_jwt" {
  bash -c '
    REPO_ROOT="$1"
    STREAM_LOG="$2"
    SCRIPT_DIR="$REPO_ROOT/scripts"
    PLUGINS_DIR="$(dirname "$STREAM_LOG")/plugins"
    mkdir -p "$PLUGINS_DIR"
    touch "$PLUGINS_DIR/eso.sh"

    source "$REPO_ROOT/scripts/lib/foundation/scripts/lib/system.sh"
    source "$REPO_ROOT/scripts/plugins/vault.sh"

    _info() { :; }
    _vault_policy_exists() { return 1; }
    _vault_login() { return 0; }
    _kubectl() { cat >/dev/null; return 0; }
    _vault_exec_stream() {
      printf "VAULT_EXEC_STREAM ARGV: %s\n" "$*" >> "$STREAM_LOG"
      cat >> "$STREAM_LOG"
      return 0
    }

    _vault_set_eso_reader
  ' bash "$REPO_ROOT" "$STREAM_LOG" </dev/null

  local captured
  captured="$(cat "$STREAM_LOG")"
  assert_clean_k8s_auth_config "$captured" "_vault_set_eso_reader"
}

@test "E1 [M1, N1, N2]: _vault_configure_secret_reader_role writes auth config without token_reviewer_jwt or disable_local_ca_jwt" {
  bash -c '
    REPO_ROOT="$1"
    STREAM_LOG="$2"
    SCRIPT_DIR="$REPO_ROOT/scripts"
    PLUGINS_DIR="$(dirname "$STREAM_LOG")/plugins"
    mkdir -p "$PLUGINS_DIR"
    touch "$PLUGINS_DIR/eso.sh"

    source "$REPO_ROOT/scripts/lib/foundation/scripts/lib/system.sh"
    source "$REPO_ROOT/scripts/plugins/vault.sh"

    _info() { :; }
    _vault_login() { return 0; }
    _vault_exec() {
      if [[ "$*" == *"vault secrets list"* ]]; then
        echo "{\"secret/\":{}}"
      elif [[ "$*" == *"vault auth list"* ]]; then
        echo "{\"kubernetes/\":{}}"
      fi
    }
    _kubectl() { cat >/dev/null; return 0; }
    _vault_build_policy_hcl() { _VAULT_POLICY_HCL="path \"secret/*\" { capabilities = [\"read\"] }"; }
    _vault_exec_stream() {
      printf "VAULT_EXEC_STREAM ARGV: %s\n" "$*" >> "$STREAM_LOG"
      cat >> "$STREAM_LOG"
      return 0
    }

    _vault_configure_secret_reader_role
  ' bash "$REPO_ROOT" "$STREAM_LOG" </dev/null

  local captured
  captured="$(cat "$STREAM_LOG")"
  assert_clean_k8s_auth_config "$captured" "_vault_configure_secret_reader_role"
}

@test "E1 [M1, N1, N2]: _hub_data_repoint_vault writes auth config without token_reviewer_jwt or disable_local_ca_jwt" {
  bash -c '
    REPO_ROOT="$1"
    STREAM_LOG="$2"
    SCRIPT_DIR="$REPO_ROOT/scripts"
    PLUGINS_DIR="$REPO_ROOT/scripts/plugins"

    source "$REPO_ROOT/scripts/lib/foundation/scripts/lib/system.sh"
    source "$REPO_ROOT/scripts/plugins/hub_data.sh"

    _info() { :; }
    _hub_data_generate_root() { printf "fake-root-token"; }
    _secret_load_data() { [[ "$2" == *:count ]] && printf 1 || printf SHARD; }
    _vault_dr_shard_valid() { return 0; }
    _vault_cache_unseal_keys() { return 0; }
    _hub_recovery_sync_vault_root_token() { return 0; }
    _kubectl() { cat >/dev/null; return 0; }
    _vault_exec_stream() {
      printf "VAULT_EXEC_STREAM ARGV: %s\n" "$*" >> "$STREAM_LOG"
      cat >> "$STREAM_LOG"
      return 0
    }

    _hub_data_repoint_vault ctx
  ' bash "$REPO_ROOT" "$STREAM_LOG" </dev/null

  local captured
  captured="$(cat "$STREAM_LOG")"
  assert_clean_k8s_auth_config "$captured" "_hub_data_repoint_vault"
}

@test "E1 [M1, N1, N2]: test_vault writes auth config without token_reviewer_jwt or disable_local_ca_jwt" {
  bash -c '
    REPO_ROOT="$1"
    KUBECTL_ARGV_LOG="$2"
    KUBECTL_STDIN_LOG="$3"

    source "$REPO_ROOT/scripts/lib/foundation/scripts/lib/system.sh"
    source "$REPO_ROOT/scripts/lib/test.sh"

    _info() { :; }
    _err() { return 1; }
    VAULT_RELEASE_DEFAULT=vault

    _kubectl() {
      printf "KUBECTL ARGV: %s\n" "$*" >> "$KUBECTL_ARGV_LOG"
      if [[ "$*" == *"exec -i"* ]]; then
        local stdin_input
        stdin_input=$(cat)
        if [[ -n "$stdin_input" ]]; then
          printf "KUBECTL STDIN: %s\n" "$stdin_input" >> "$KUBECTL_STDIN_LOG"
        fi
      elif [[ "$*" == *"apply -f -"* ]]; then
        cat >/dev/null
      fi

      local args="$*"
      if [[ "$args" == *"get secret vault-root"* ]]; then
        printf "%s" "fake-root-token" | base64
      elif [[ "$args" == *"cat /tmp/secret"* ]]; then
        printf "success"
      elif [[ "$args" == *"create token"* ]]; then
        printf "fake-jwt"
      elif [[ "$args" == *"auth/kubernetes/login"* ]]; then
        printf "fake-vault-token"
      elif [[ "$args" == *"vault kv get"* ]]; then
        printf "success"
      fi
      return 0
    }

    test_vault
  ' bash "$REPO_ROOT" "$KUBECTL_ARGV_LOG" "$KUBECTL_STDIN_LOG" </dev/null

  local captured
  captured="$(cat "$KUBECTL_ARGV_LOG")"
  assert_clean_k8s_auth_config "$captured" "test_vault"
}

@test "E2 [M2, N3]: test_vault passes root token on stdin only, never in kubectl argv, trap, or xtrace" {
  local fake_token="s.test-secret-root-token-v884"

  bash -c '
    REPO_ROOT="$1"
    FAKE_TOKEN="$2"
    KUBECTL_ARGV_LOG="$3"
    KUBECTL_STDIN_LOG="$4"
    TRAP_LOG="$5"

    source "$REPO_ROOT/scripts/lib/foundation/scripts/lib/system.sh"
    source "$REPO_ROOT/scripts/lib/test.sh"

    _info() { :; }
    _err() { return 1; }
    VAULT_RELEASE_DEFAULT=vault

    _kubectl() {
      printf "%s\n" "$*" >> "$KUBECTL_ARGV_LOG"
      if [[ "$*" == *"exec -i"* ]]; then
        local stdin_input
        stdin_input=$(cat)
        if [[ -n "$stdin_input" ]]; then
          printf "%s\n" "$stdin_input" >> "$KUBECTL_STDIN_LOG"
        fi
      elif [[ "$*" == *"apply -f -"* ]]; then
        cat >/dev/null
      fi

      local args="$*"
      if [[ "$args" == *"get secret vault-root"* ]]; then
        printf "%s" "$FAKE_TOKEN" | base64
      elif [[ "$args" == *"cat /tmp/secret"* ]]; then
        printf "success"
      elif [[ "$args" == *"create token"* ]]; then
        printf "fake-jwt"
      elif [[ "$args" == *"auth/kubernetes/login"* ]]; then
        printf "fake-vault-token"
      elif [[ "$args" == *"vault kv get"* ]]; then
        printf "success"
      fi
      return 0
    }

    set -x
    test_vault
    trap -p EXIT > "$TRAP_LOG"
    trap -p TERM >> "$TRAP_LOG"
  ' bash "$REPO_ROOT" "$fake_token" "$KUBECTL_ARGV_LOG" "$KUBECTL_STDIN_LOG" "$TRAP_LOG" </dev/null 2> "$XTRACE_LOG"

  # 1. Root token must arrive on stdin for vault commands (M2 positive check)
  run grep -F "$fake_token" "$KUBECTL_STDIN_LOG"
  [ "$status" -eq 0 ]

  # 1b. All five exec -i vault calls (3 in test_vault, 2 in the EXIT-trap cleanup) get the token on stdin
  [ "$(grep -cF "$fake_token" "$KUBECTL_STDIN_LOG")" -eq 5 ]

  # 2. Root token must NOT appear in any kubectl argv (M2, N3)
  run grep -F "$fake_token" "$KUBECTL_ARGV_LOG"
  [ "$status" -ne 0 ]

  # 3. Root token must NOT appear in trap string (M2, N3)
  run grep -F "$fake_token" "$TRAP_LOG"
  [ "$status" -ne 0 ]

  # 4. Root token must NOT appear in xtrace output under set -x (N3)
  run grep -F "$fake_token" "$XTRACE_LOG"
  [ "$status" -ne 0 ]
}
