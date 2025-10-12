#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  source "${BATS_TEST_DIRNAME}/../../lib/system.sh"
  init_test_env
}

@test "_ensure_cifs_utils succeeds when mount.cifs already exists" {
  _command_exist() {
    if [[ "$1" == "mount.cifs" ]]; then
      return 0
    fi
    return 1
  }
  export -f _command_exist
  export_stubs

  run _ensure_cifs_utils
  [ "$status" -eq 0 ]
  [ ! -s "$RUN_LOG" ]
}

@test "_ensure_cifs_utils installs cifs-utils via apt when missing" {
  CIFS_PRESENT=0
  _command_exist() {
    case "$1" in
      mount.cifs)
        if (( CIFS_PRESENT )); then
          return 0
        fi
        return 1
        ;;
      apt-get|sudo)
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  }
  _is_mac() { return 1; }
  _is_debian_family() { return 0; }
  _is_redhat_family() { return 1; }
  _is_wsl() { return 1; }
  _run_command() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit|--soft|--quiet|--prefer-sudo|--require-sudo) shift ;;
        --probe) shift 2 ;;
        --) shift; break ;;
        *) break ;;
      esac
    done
    local cmd="$*"
    echo "$cmd" >>"$RUN_LOG"
    if [[ "$cmd" == "env DEBIAN_FRONTEND=noninteractive apt-get install -y cifs-utils" ]]; then
      CIFS_PRESENT=1
    fi
    return 0
  }
  export -f _command_exist _is_mac _is_debian_family _is_redhat_family _is_wsl _run_command
  export_stubs

  run _ensure_cifs_utils
  [ "$status" -eq 0 ]
  grep -q 'apt-get update -y' "$RUN_LOG"
  grep -q 'apt-get install -y cifs-utils' "$RUN_LOG"
}

@test "_ensure_cifs_utils installs cifs-utils via dnf when missing" {
  CIFS_PRESENT=0
  _command_exist() {
    case "$1" in
      mount.cifs)
        if (( CIFS_PRESENT )); then
          return 0
        fi
        return 1
        ;;
      dnf|sudo)
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  }
  _is_mac() { return 1; }
  _is_debian_family() { return 1; }
  _is_redhat_family() { return 0; }
  _is_wsl() { return 1; }
  _run_command() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --no-exit|--soft|--quiet|--prefer-sudo|--require-sudo) shift ;;
        --probe) shift 2 ;;
        --) shift; break ;;
        *) break ;;
      esac
    done
    local cmd="$*"
    echo "$cmd" >>"$RUN_LOG"
    if [[ "$cmd" == "dnf install -y cifs-utils" ]]; then
      CIFS_PRESENT=1
    fi
    return 0
  }
  export -f _command_exist _is_mac _is_debian_family _is_redhat_family _is_wsl _run_command
  export_stubs

  run _ensure_cifs_utils
  [ "$status" -eq 0 ]
  grep -q 'dnf install -y cifs-utils' "$RUN_LOG"
}

@test "_ensure_cifs_utils warns when platform unsupported" {
  _command_exist() { return 1; }
  _is_mac() { return 0; }
  _is_debian_family() { return 1; }
  _is_redhat_family() { return 1; }
  _is_wsl() { return 1; }
  export -f _command_exist _is_mac _is_debian_family _is_redhat_family _is_wsl
  export_stubs

  run _ensure_cifs_utils
  [ "$status" -eq 1 ]
  [[ "$output" == *"cifs-utils install not supported on macOS"* ]]
}
