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
  export TUNNEL_VAULT_PLIST_PATH="${BATS_TEST_TMPDIR}/com.k3d-manager.ssh-tunnel-vault.plist"
  export TUNNEL_VAULT_WRAPPER_PATH="${BATS_TEST_TMPDIR}/com.k3d-manager.ssh-tunnel-vault.sh"
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
  _tunnel_vault_launchd_loaded() { return 0; }
  export -f _tunnel_autossh_path _tunnel_is_running _tunnel_vault_launchd_loaded
  run tunnel_start
  [ "$status" -eq 0 ]
  [[ "$output" == *"already running"* ]]
}

@test "tunnel_stop is idempotent when not running" {
  _tunnel_launchd_loaded() { return 1; }
  _tunnel_is_running() { return 1; }
  _tunnel_vault_launchd_loaded() { return 1; }
  _tunnel_vault_is_running() { return 1; }
  export -f _tunnel_launchd_loaded _tunnel_is_running _tunnel_vault_launchd_loaded _tunnel_vault_is_running
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
  grep -q "0.0.0.0:6443:localhost:6443" "${TUNNEL_PLIST_PATH}"
  grep -q "load" "${BATS_TEST_TMPDIR}/launchctl.log"
}

@test "main tunnel plist contains only the API forward" {
  _tunnel_autossh_path() { echo "/usr/local/bin/autossh"; }
  export -f _tunnel_autossh_path
  _tunnel_write_plist
  grep -q '<string>-L</string>' "${TUNNEL_PLIST_PATH}"
  ! grep -q '<string>-R</string>' "${TUNNEL_PLIST_PATH}"
}

@test "vault agent clears stale 8200 and owns the reverse forward" {
  _tunnel_write_vault_agent
  grep -q 'fuser -k -n tcp 8200' "${TUNNEL_VAULT_WRAPPER_PATH}"
  grep -q 'ExitOnForwardFailure=yes' "${TUNNEL_VAULT_WRAPPER_PATH}"
  grep -q -- '-R 8200:127.0.0.1:18200' "${TUNNEL_VAULT_WRAPPER_PATH}"
  grep -q 'KeepAlive' "${TUNNEL_VAULT_PLIST_PATH}"
  grep -q "${TUNNEL_VAULT_WRAPPER_PATH}" "${TUNNEL_VAULT_PLIST_PATH}"
}

@test "tunnel_start migrates a running main plist that still has the reverse forward" {
  _tunnel_autossh_path() { echo "/usr/local/bin/autossh"; }
  _tunnel_is_running() { return 0; }
  _tunnel_vault_launchd_loaded() { return 0; }
  uname() { echo "Darwin"; }
  launchctl() { echo "launchctl $*" >> "${BATS_TEST_TMPDIR}/launchctl.log"; }
  printf '<string>-R</string>\n' > "${TUNNEL_PLIST_PATH}"
  export -f _tunnel_autossh_path _tunnel_is_running _tunnel_vault_launchd_loaded uname launchctl
  run tunnel_start
  [ "$status" -eq 0 ]
  [[ "$output" != *"already running"* ]]
  grep -q "load -w ${TUNNEL_PLIST_PATH}" "${BATS_TEST_TMPDIR}/launchctl.log"
  grep -q "load -w ${TUNNEL_VAULT_PLIST_PATH}" "${BATS_TEST_TMPDIR}/launchctl.log"
}

@test "tunnel_stop unloads the vault agent when loaded" {
  _tunnel_launchd_loaded() { return 1; }
  _tunnel_is_running() { return 1; }
  _tunnel_vault_launchd_loaded() { return 0; }
  _tunnel_vault_is_running() { return 1; }
  launchctl() { echo "launchctl $*" >> "${BATS_TEST_TMPDIR}/launchctl.log"; }
  export -f _tunnel_launchd_loaded _tunnel_is_running _tunnel_vault_launchd_loaded _tunnel_vault_is_running launchctl
  run tunnel_stop
  [ "$status" -eq 0 ]
  grep -q "unload -w ${TUNNEL_VAULT_PLIST_PATH}" "${BATS_TEST_TMPDIR}/launchctl.log"
}
