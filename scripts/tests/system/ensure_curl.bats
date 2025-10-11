#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  source "${BATS_TEST_DIRNAME}/../../lib/system.sh"
  init_test_env
}

@test "_ensure_curl returns success when curl already exists" {
  _command_exist() {
    if [[ "$1" == "curl" ]]; then
      return 0
    fi
    return 1
  }
  export -f _command_exist
  export_stubs

  run _ensure_curl
  [ "$status" -eq 0 ]
  [ ! -s "$RUN_LOG" ]
}

@test "_ensure_curl installs curl via apt when missing" {
  CURL_PRESENT=0
  _command_exist() {
    case "$1" in
      curl)
        if (( CURL_PRESENT )); then
          return 0
        fi
        return 1
        ;;
      apt-get) return 0 ;;
      sudo) return 0 ;;
      *) return 1 ;;
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
    if [[ "$cmd" == "env DEBIAN_FRONTEND=noninteractive apt-get install -y curl" ]]; then
      CURL_PRESENT=1
    fi
    return 0
  }
  export -f _command_exist _is_mac _is_debian_family _is_redhat_family _is_wsl _run_command
  export_stubs

  run _ensure_curl
  [ "$status" -eq 0 ]
  grep -q 'apt-get update -y' "$RUN_LOG"
  grep -q 'apt-get install -y curl' "$RUN_LOG"
}

@test "_ensure_curl warns when platform unsupported" {
  _command_exist() { return 1; }
  _is_mac() { return 1; }
  _is_debian_family() { return 1; }
  _is_redhat_family() { return 1; }
  _is_wsl() { return 1; }
  export -f _command_exist _is_mac _is_debian_family _is_redhat_family _is_wsl
  export_stubs

  run _ensure_curl
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported platform for automatic curl installation."* ]]
}
