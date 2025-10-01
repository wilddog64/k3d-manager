#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/lib/system.sh"
}

@test "no-op when bats already meets requirement" {
  export_stubs

  bats() { printf 'Bats 1.6.0\n'; }
  _command_exist() { [[ "$1" == bats ]]; }
  _sudo_available() { return 1; }
  export -f bats _command_exist _sudo_available

  run _ensure_bats
  [ "$status" -eq 0 ]
  [ ! -s "$RUN_LOG" ]
}

@test "falls back to source install when sudo unavailable" {
  export_stubs

  bats_version_output="Bats 1.4.0"
  bats() { printf '%s\n' "$bats_version_output"; }
  _command_exist() {
    case "$1" in
      bats|apt-get|curl|tar) return 0 ;;
      *) return 1 ;;
    esac
  }
  _sudo_available() { return 1; }
  _install_bats_from_source() {
    echo "install-bats-source" >> "$RUN_LOG"
    bats_version_output="Bats 1.10.0"
    return 0
  }
  export -f bats _command_exist _sudo_available _install_bats_from_source

  run _ensure_bats
  [ "$status" -eq 0 ]
  ! grep -q '^apt-get ' "$RUN_LOG"
  grep -q 'install-bats-source' "$RUN_LOG"
}

@test "uses package manager when sudo available" {
  export_stubs

  bats_version_output="Bats 1.4.0"
  bats() { printf '%s\n' "$bats_version_output"; }
  _command_exist() {
    case "$1" in
      bats|apt-get|curl|tar) return 0 ;;
      *) return 1 ;;
    esac
  }
  _sudo_available() { return 0; }
  _install_bats_from_source() {
    echo "unexpected-source" >> "$RUN_LOG"
    return 1
  }
  _run_command() {
    local cmd
    local -a cmd_args=()

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --prefer-sudo|--require-sudo|--quiet|--no-exit|--soft) shift ;;
        --probe) shift 2 ;;
        --) shift; break ;;
        *) break ;;
      esac
    done

    cmd="$1"
    shift || true
    while [[ $# -gt 0 ]]; do
      cmd_args+=("$1")
      shift
    done

    printf '%s' "$cmd" >> "$RUN_LOG"
    if ((${#cmd_args[@]})); then
      printf ' %s' "${cmd_args[@]}" >> "$RUN_LOG"
    fi
    printf '
' >> "$RUN_LOG"

    if [[ "$cmd" == apt-get && "${cmd_args[0]:-}" == install ]]; then
      bats_version_output="Bats 1.10.0"
    fi

    return 0
  }
  export -f bats _command_exist _sudo_available _install_bats_from_source _run_command

  run _ensure_bats
  [ "$status" -eq 0 ]
  grep -q '^apt-get update' "$RUN_LOG"
  grep -q '^apt-get install -y bats' "$RUN_LOG"
  ! grep -q 'unexpected-source' "$RUN_LOG"
}
