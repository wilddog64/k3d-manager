#!/usr/bin/env bats
# shellcheck shell=bash disable=SC1091,SC2329

setup() {
  SYSTEM_LIB="${BATS_TEST_DIRNAME}/../../lib/system.sh"
  CDP_LIB="${BATS_TEST_DIRNAME}/../../lib/acg/cdp.sh"
  # shellcheck source=/dev/null
  source "$SYSTEM_LIB"
  # shellcheck source=/dev/null
  source "$CDP_LIB"
}

bats_require_minimum_version 1.5.0

@test "_browser_launch: reuses the CDP browser and runs the session check when it is healthy" {
  _command_exist() { [[ "$1" == curl ]]; }
  _run_command() { return 0; }
  _cdp_connectable() { return 0; }
  _info() { :; }
  _cdp_ensure_acg_session() { echo "session-check"; return 0; }
  export -f _command_exist _run_command _cdp_connectable _info _cdp_ensure_acg_session

  run _browser_launch
  [ "$status" -eq 0 ]
  [ "$output" = "session-check" ]

  unset -f _command_exist _run_command _cdp_connectable _info _cdp_ensure_acg_session
}

@test "_browser_launch: reclaims an undriveable CDP browser then relaunches the managed Chromium" {
  fake_chromium="${BATS_TEST_TMPDIR}/fake-chromium"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$fake_chromium"
  chmod +x "$fake_chromium"
  reclaim_log="${BATS_TEST_TMPDIR}/reclaim.log"

  _command_exist() { [[ "$1" == curl ]]; }
  _run_command() { return 0; }
  _cdp_connectable() { return 1; }
  _cdp_kill_port_listener() { echo "reclaimed" >>"$reclaim_log"; }
  _cdp_stop_chrome_cdp_agent() { :; }
  _cdp_remove_stale_singleton_lock() { :; }
  _info() { :; }
  uname() { echo "Darwin"; }
  node() { printf '%s' "$fake_chromium"; }
  _antigravity_browser_ready() { :; }
  _cdp_ensure_acg_session() { echo "relaunched-session-check"; return 0; }
  export fake_chromium reclaim_log
  export -f _command_exist _run_command _cdp_connectable _cdp_kill_port_listener _cdp_stop_chrome_cdp_agent _cdp_remove_stale_singleton_lock _info uname node _antigravity_browser_ready _cdp_ensure_acg_session

  run _browser_launch
  [ "$status" -eq 0 ]
  [ "$output" = "relaunched-session-check" ]
  [ -f "$reclaim_log" ]

  unset -f _command_exist _run_command _cdp_connectable _cdp_kill_port_listener _cdp_stop_chrome_cdp_agent _cdp_remove_stale_singleton_lock _info uname node _antigravity_browser_ready _cdp_ensure_acg_session
}

@test "_browser_launch: launches the managed Chromium then runs the session check" {
  fake_chromium="${BATS_TEST_TMPDIR}/fake-chromium"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$fake_chromium"
  chmod +x "$fake_chromium"

  _command_exist() { [[ "$1" == curl ]]; }
  _run_command() { return 1; }
  _cdp_stop_chrome_cdp_agent() { :; }
  _cdp_remove_stale_singleton_lock() { :; }
  _info() { :; }
  uname() { echo "Darwin"; }
  node() { printf '%s' "$fake_chromium"; }
  _antigravity_browser_ready() { :; }
  _cdp_ensure_acg_session() { echo "launched-session-check"; return 0; }
  export fake_chromium
  export -f _command_exist _run_command _cdp_stop_chrome_cdp_agent _cdp_remove_stale_singleton_lock _info uname node _antigravity_browser_ready _cdp_ensure_acg_session

  run _browser_launch
  [ "$status" -eq 0 ]
  [ "$output" = "launched-session-check" ]

  unset -f _command_exist _run_command _cdp_stop_chrome_cdp_agent _cdp_remove_stale_singleton_lock _info uname node _antigravity_browser_ready _cdp_ensure_acg_session
}

@test "_browser_launch: K3DM_ACG_SKIP_SESSION_CHECK=1 still bypasses the session check end-to-end" {
  _command_exist() { [[ "$1" == curl ]]; }
  _run_command() { return 0; }
  _info() { echo "$*"; }
  _err() { echo "$*"; return 1; }
  export -f _command_exist _run_command _info _err
  export K3DM_ACG_SKIP_SESSION_CHECK=1
  export _LIB_ACG_ROOT="${BATS_TEST_TMPDIR}/missing-acg-root"

  run _browser_launch
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping ACG/Pluralsight session check"* ]]

  unset K3DM_ACG_SKIP_SESSION_CHECK _LIB_ACG_ROOT
  unset -f _command_exist _run_command _info _err
}
