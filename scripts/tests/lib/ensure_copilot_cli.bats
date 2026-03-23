#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/lib/system.sh"
}

@test "no-op when copilot binary already present" {
  export_stubs

  _command_exist() {
    [[ "$1" == copilot ]]
  }
  export -f _command_exist

  run _ensure_copilot_cli
  [ "$status" -eq 0 ]
  [ ! -s "$RUN_LOG" ]
}

@test "installs via brew when available" {
  export_stubs

  copilot_ready=0
  _command_exist() {
    case "$1" in
      copilot) [[ "$copilot_ready" -eq 1 ]] ;;
      brew) return 0 ;;
      *) return 1 ;;
    esac
  }
  _run_command() {
    local payload="$*"
    printf '%s\n' "$payload" >> "$RUN_LOG"
    if [[ "$payload" == *"brew install copilot-cli"* ]]; then
      copilot_ready=1
    fi
    return 0
  }
  export -f _command_exist _run_command

  run _ensure_copilot_cli
  [ "$status" -eq 0 ]
  grep -q 'brew install copilot-cli' "$RUN_LOG"
}

@test "falls back to release installer when brew missing" {
  export_stubs

  copilot_ready=0
  _command_exist() {
    case "$1" in
      copilot) [[ "$copilot_ready" -eq 1 ]] ;;
      brew) return 1 ;;
      *) return 1 ;;
    esac
  }
  _install_copilot_from_release() {
    copilot_ready=1
    echo "copilot-release" >> "$RUN_LOG"
    return 0
  }
  export -f _command_exist _install_copilot_from_release

  run _ensure_copilot_cli
  [ "$status" -eq 0 ]
  grep -q '^copilot-release$' "$RUN_LOG"
}

@test "fails when authentication is invalid and AI gated" {
   export_stubs

   copilot_ready=1
   export K3DM_ENABLE_AI=1
  _command_exist() {
    [[ "$1" == copilot ]]
  }
  _run_command() {
    local payload="$*"
    if [[ "$payload" == *"copilot auth status"* ]]; then
      return 1
    fi
    printf '%s\n' "$payload" >> "$RUN_LOG"
    return 0
  }
  export -f _command_exist _run_command

  run _ensure_copilot_cli
  [ "$status" -ne 0 ]
   [[ "$output" == *"Copilot CLI authentication failed"* ]]
}

@test "_copilot_auth_check passes with real COPILOT_GITHUB_TOKEN" {
  if [[ -z "${COPILOT_GITHUB_TOKEN:-}" ]]; then
    skip "COPILOT_GITHUB_TOKEN not set — skipping live auth check"
  fi
  if ! command -v copilot >/dev/null 2>&1; then
    skip "copilot binary not found — skipping live auth check"
  fi

  export K3DM_ENABLE_AI=1
  # Do NOT stub _run_command — use the real copilot binary
  run _copilot_auth_check
  [ "$status" -eq 0 ]
}
