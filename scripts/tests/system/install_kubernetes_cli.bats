#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  source "${BATS_TEST_DIRNAME}/../../lib/system.sh"
  init_test_env
}

@test "installs kubectl via brew on macOS" {
  _is_redhat_family() { return 1; }
  _is_debian_family() { return 1; }
  _is_wsl() { return 1; }
  _is_mac() { return 0; }
  _command_exist() { return 1; }
  export -f _is_redhat_family _is_debian_family _is_wsl _is_mac _command_exist
  export_stubs

  run _install_kubernetes_cli
  [ "$status" -eq 0 ]
  read_lines "$RUN_LOG" log
  [ "${log[0]}" = "brew install kubectl" ]
}

@test "uses non-macOS installers when not on macOS" {
  _is_redhat_family() { return 1; }
  _is_debian_family() { return 0; }
  _is_wsl() { return 1; }
  _is_mac() { return 1; }
  _command_exist() { return 1; }
  export -f _is_redhat_family _is_debian_family _is_wsl _is_mac _command_exist
  export_stubs

  run _install_kubernetes_cli
  [ "$status" -eq 0 ]
  ! grep -q 'brew install kubectl' "$RUN_LOG"
  grep -q 'sudo apt-get install -y kubectl' "$RUN_LOG"
}
