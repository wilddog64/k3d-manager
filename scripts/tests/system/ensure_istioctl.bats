#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  source "${BATS_TEST_DIRNAME}/../../lib/system.sh"
  init_test_env
}

@test "_ensure_istioctl returns success when istioctl already exists" {
  _command_exist() {
    if [[ "$1" == "istioctl" ]]; then
      return 0
    fi
    command -v "$1" >/dev/null 2>&1
  }
  _install_istioctl() { echo "install_istioctl" >>"$RUN_LOG"; }
  export -f _command_exist _install_istioctl
  export_stubs

  run _ensure_istioctl
  [ "$status" -eq 0 ]
  ! grep -q 'install_istioctl' "$RUN_LOG"
}

@test "_ensure_istioctl installs istioctl when missing" {
  ISTIOCTL_PRESENT=0
  _command_exist() {
    if [[ "$1" == "istioctl" ]]; then
      if (( ISTIOCTL_PRESENT )); then
        return 0
      fi
      return 1
    fi
    command -v "$1" >/dev/null 2>&1
  }
  _install_istioctl() {
    echo "install_istioctl" >>"$RUN_LOG"
    ISTIOCTL_PRESENT=1
    return 0
  }
  export -f _command_exist _install_istioctl
  export_stubs

  run _ensure_istioctl
  [ "$status" -eq 0 ]
  grep -q 'install_istioctl' "$RUN_LOG"
}

@test "_ensure_istioctl fails when install does not provide binary" {
  _command_exist() { return 1; }
  _install_istioctl() {
    echo "install_istioctl" >>"$RUN_LOG"
    return 1
  }
  export -f _command_exist _install_istioctl
  export_stubs

  run _ensure_istioctl
  [ "$status" -eq 1 ]
  grep -q 'install_istioctl' "$RUN_LOG"
  [[ "$output" == *"istioctl not available"* ]]
}
