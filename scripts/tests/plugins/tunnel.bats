#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  export SCRIPT_DIR="${BATS_TEST_DIRNAME}/../.."
  export PLUGINS_DIR="${SCRIPT_DIR}/plugins"
  export TUNNEL_SSH_HOST="ubuntu"
  export TUNNEL_LOCAL_PORT="6443"
  export TUNNEL_REMOTE_PORT="6443"
  export TUNNEL_BIND_ADDR="0.0.0.0"
  export TUNNEL_LAUNCHD_LABEL="com.k3d-manager.ssh-tunnel"
  export TUNNEL_PLIST_PATH="${BATS_TEST_TMPDIR}/com.k3d-manager.ssh-tunnel.plist"
  source "${PLUGINS_DIR}/tunnel.sh"
}

@test "tunnel_status reports not running when process absent" {
  pgrep() { return 1; }
  launchctl() { return 1; }
  export -f pgrep launchctl
  run tunnel_status
  [ "$status" -eq 1 ]
  [[ "$output" == *"process: not running"* ]]
}

@test "tunnel_status reports running when process present" {
  pgrep() { return 0; }
  launchctl() { return 0; }
  export -f pgrep launchctl
  run tunnel_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"process: running"* ]]
}

@test "tunnel_start fails when autossh not installed" {
  _tunnel_autossh_path() { echo ""; }
  export -f _tunnel_autossh_path
  run tunnel_start
  [ "$status" -eq 1 ]
  [[ "$output" == *"autossh not found"* ]]
}

@test "tunnel_start is idempotent when already running" {
  _tunnel_autossh_path() { echo "/usr/local/bin/autossh"; }
  _tunnel_is_running() { return 0; }
  export -f _tunnel_autossh_path _tunnel_is_running
  run tunnel_start
  [ "$status" -eq 0 ]
  [[ "$output" == *"already running"* ]]
}

@test "tunnel_stop is idempotent when not running" {
  _tunnel_launchd_loaded() { return 1; }
  _tunnel_is_running() { return 1; }
  export -f _tunnel_launchd_loaded _tunnel_is_running
  run tunnel_stop
  [ "$status" -eq 0 ]
  [[ "$output" == *"stopped"* ]]
}

@test "tunnel_start writes plist and calls launchctl load" {
  _tunnel_autossh_path() { echo "/usr/local/bin/autossh"; }
  _tunnel_is_running() { return 1; }
  uname() { echo "Darwin"; }
  launchctl() { echo "launchctl $*" >> "${BATS_TEST_TMPDIR}/launchctl.log"; }
  export -f _tunnel_autossh_path _tunnel_is_running uname launchctl
  run tunnel_start
  [ "$status" -eq 0 ]
  [[ -f "${TUNNEL_PLIST_PATH}" ]]
  grep -q "8200:127.0.0.1:18200" "${TUNNEL_PLIST_PATH}"
  grep -q "load" "${BATS_TEST_TMPDIR}/launchctl.log"
}
