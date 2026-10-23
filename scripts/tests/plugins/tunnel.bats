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
  export TUNNEL_FORWARD_WRAPPER_PATH="${BATS_TEST_TMPDIR}/com.k3d-manager.ssh-tunnel.sh"
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
  grep -q "0.0.0.0:6443:localhost:6443" "${TUNNEL_FORWARD_WRAPPER_PATH}"
  grep -q "load" "${BATS_TEST_TMPDIR}/launchctl.log"
}

@test "main tunnel plist contains only the API forward" {
  _tunnel_autossh_path() { echo "/usr/local/bin/autossh"; }
  export -f _tunnel_autossh_path
  _tunnel_write_plist
  grep -q -- '-L 0.0.0.0:6443:localhost:6443' "${TUNNEL_FORWARD_WRAPPER_PATH}"
  run grep -q '-R' "${TUNNEL_FORWARD_WRAPPER_PATH}"
  [ "$status" -ne 0 ]
}

@test "vault agent clears stale 8200 and owns the reverse forward" {
  _tunnel_write_vault_agent
  grep -q 'fuser -k -n tcp 8200' "${TUNNEL_VAULT_WRAPPER_PATH}"
  grep -q 'sudo fuser -k -n tcp 8200' "${TUNNEL_VAULT_WRAPPER_PATH}"
  run bash -n "${TUNNEL_VAULT_WRAPPER_PATH}"
  [ "$status" -eq 0 ]
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

@test "tunnel.sh does not disguise sudo" {
  run grep -F 'su""do' "${PLUGINS_DIR}/tunnel.sh"
  [ "$status" -ne 0 ]
}

@test "exact destination matching excludes Hostinger and accepts sandbox" {
  pgrep() {
    local _pattern="${2:-}"
    printf '%s\n' \
      '/opt/homebrew/bin/autossh -M 0 -o ExitOnForwardFailure=yes -L 0.0.0.0:6443:localhost:6443 -N ubuntu@srv1754834.hstgr.cloud' \
      | grep -E -- "${_pattern}" >/dev/null
  }
  export -f pgrep
  run _tunnel_is_running
  [ "$status" -ne 0 ]

  pgrep() {
    local _pattern="${2:-}"
    printf '%s\n' '/opt/homebrew/bin/autossh -M 0 -o ExitOnForwardFailure=yes -L 0.0.0.0:16443:localhost:6443 -N ubuntu' \
      | grep -E -- "${_pattern}" >/dev/null
  }
  export -f pgrep
  run _tunnel_is_running
  [ "$status" -eq 0 ]
}

@test "sandbox tunnel_start uses sandbox agents and does not accept Hostinger autossh" {
  unset TUNNEL_LOCAL_PORT TUNNEL_LAUNCHD_LABEL TUNNEL_PLIST_PATH
  unset TUNNEL_VAULT_LAUNCHD_LABEL TUNNEL_VAULT_PLIST_PATH TUNNEL_VAULT_WRAPPER_PATH TUNNEL_FORWARD_WRAPPER_PATH
  export HOME="${BATS_TEST_TMPDIR}/sandbox-home"
  pgrep() {
    local _pattern="${2:-}"
    printf '%s\n' '/opt/homebrew/bin/autossh -M 0 -o ExitOnForwardFailure=yes -L 0.0.0.0:6443:localhost:6443 -N ubuntu@srv1754834.hstgr.cloud' \
      | grep -E -- "${_pattern}" >/dev/null
  }
  launchctl() { return 0; }
  _tunnel_autossh_path() { echo "/usr/local/bin/autossh"; }
  uname() { echo Darwin; }
  export -f pgrep launchctl _tunnel_autossh_path uname
  export TUNNEL_SCOPE=sandbox
  run tunnel_start
  [ "$status" -eq 0 ]
  [[ "$output" != *"already running"* ]]
  grep -q '0.0.0.0:16443:localhost:6443' "${HOME}/Library/LaunchAgents/com.k3d-manager.sandbox.ssh-tunnel.sh"
  grep -q -- '-R 8200:127.0.0.1:18200' "${HOME}/Library/LaunchAgents/com.k3d-manager.sandbox.ssh-tunnel-vault.sh"
  [ ! -e "${HOME}/Library/LaunchAgents/com.k3d-manager.ssh-tunnel.plist" ]
  [ ! -e "${HOME}/Library/LaunchAgents/com.k3d-manager.ssh-tunnel-vault.plist" ]
}

@test "tunnel scope resolves fresh values on every call" {
  TUNNEL_SCOPE=sandbox _tunnel_resolve_scope
  TUNNEL_SCOPE= _tunnel_resolve_scope
  [ "${_TUNNEL_LAUNCHD_LABEL}" = "com.k3d-manager.ssh-tunnel" ]
  [ "${_TUNNEL_LOCAL_PORT}" = "6443" ]
}

@test "sandbox tunnel_stop uses destination-bounded kill patterns" {
  _tunnel_launchd_loaded() { return 1; }
  _tunnel_is_running() { return 0; }
  _tunnel_vault_launchd_loaded() { return 1; }
  _tunnel_vault_is_running() { return 0; }
  pkill() { printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/pkill-patterns.log"; }
  export -f _tunnel_launchd_loaded _tunnel_is_running _tunnel_vault_launchd_loaded _tunnel_vault_is_running pkill
  export TUNNEL_SCOPE=sandbox
  run tunnel_stop
  [ "$status" -eq 0 ]
  grep -Fq -- 'autossh .* -N ubuntu$' "${BATS_TEST_TMPDIR}/pkill-patterns.log"
  grep -Fq -- 'ssh -N .*-R 8200:127\.0\.0\.1:18200 ubuntu$' "${BATS_TEST_TMPDIR}/pkill-patterns.log"
}


@test "generated tunnel wrappers timestamp stderr and bound SSH connection time" {
  _tunnel_autossh_path() { echo "/usr/local/bin/autossh"; }
  export -f _tunnel_autossh_path
  _tunnel_write_plist
  _tunnel_write_vault_agent
  grep -Eq "date -u.*%Y-%m-%dT%H:%M:%SZ" "${TUNNEL_FORWARD_WRAPPER_PATH}"
  grep -q 'ConnectTimeout=10' "${TUNNEL_FORWARD_WRAPPER_PATH}"
  grep -q 'ServerAliveInterval=30' "${TUNNEL_FORWARD_WRAPPER_PATH}"
  grep -q 'ServerAliveCountMax=3' "${TUNNEL_FORWARD_WRAPPER_PATH}"
  grep -q 'ExitOnForwardFailure=yes' "${TUNNEL_FORWARD_WRAPPER_PATH}"
  grep -q 'ConnectTimeout=10' "${TUNNEL_VAULT_WRAPPER_PATH}"
  grep -q 'ServerAliveInterval=30' "${TUNNEL_VAULT_WRAPPER_PATH}"
  grep -q 'ServerAliveCountMax=3' "${TUNNEL_VAULT_WRAPPER_PATH}"
  grep -q 'ExitOnForwardFailure=yes' "${TUNNEL_VAULT_WRAPPER_PATH}"
  grep -Eq "date -u.*%Y-%m-%dT%H:%M:%SZ" "${TUNNEL_VAULT_WRAPPER_PATH}"
  grep -q "${TUNNEL_FORWARD_WRAPPER_PATH}" "${TUNNEL_PLIST_PATH}"
}

@test "tunnel log rotation replaces old backup only above five megabytes" {
  _tunnel_resolve_scope() { :; }
  _TUNNEL_LOG_BASE="${BATS_TEST_TMPDIR}/test-tunnel"
  printf small > "${_TUNNEL_LOG_BASE}.err"
  _tunnel_rotate_logs
  [ -f "${_TUNNEL_LOG_BASE}.err" ]
  [ ! -e "${_TUNNEL_LOG_BASE}.err.1" ]
  dd if=/dev/zero of="${_TUNNEL_LOG_BASE}.err" bs=1048576 count=6 2>/dev/null
  printf old > "${_TUNNEL_LOG_BASE}.err.1"
  _tunnel_rotate_logs
  [ ! -e "${_TUNNEL_LOG_BASE}.err" ]
  [ "$(wc -c < "${_TUNNEL_LOG_BASE}.err.1" | tr -d ' ')" -eq 6291456 ]
}

@test "cluster-down preserves Hostinger tunnel logs" {
  run grep -F '/tmp/k3d-manager-tunnel.' "${BATS_TEST_DIRNAME}/../../../bin/cluster-down"
  [ "$status" -ne 0 ]
}
