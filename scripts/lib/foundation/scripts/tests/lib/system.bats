#!/usr/bin/env bats
# shellcheck shell=bash disable=SC1091,SC2329

setup() {
  SYSTEM_LIB="${BATS_TEST_DIRNAME}/../../lib/system.sh"
  # shellcheck source=/dev/null
  source "$SYSTEM_LIB"
}

bats_require_minimum_version 1.5.0

@test "_run_command_resolve_sudo: no sudo flags → plain runner" {
  _RCRS_RUNNER=()
  _run_command_resolve_sudo "echo" 0 0 0
  [ "${_RCRS_RUNNER[0]}" = "echo" ]
  [ "${#_RCRS_RUNNER[@]}" -eq 1 ]
  unset _RCRS_RUNNER
}

@test "_run_command_resolve_sudo: require_sudo unavailable → returns 127" {
  function sudo() { return 1; }
  export -f sudo
  _RCRS_RUNNER=()
  run -127 _run_command_resolve_sudo "echo" 0 1 0
  unset -f sudo
  unset _RCRS_RUNNER
}

@test "_run_command_resolve_sudo: probe succeeds as user → plain runner" {
  _RCRS_RUNNER=()
  _run_command_resolve_sudo "true" 1 0 0 "--version"
  [ "${_RCRS_RUNNER[0]}" = "true" ]
  unset _RCRS_RUNNER
}

@test "_run_command: missing program → exits 127" {
  run -127 _run_command --soft -- __nonexistent_prog_xyz__
}

@test "_run_command: succeeds for simple command" {
  run _run_command -- echo hello
  [ "$status" -eq 0 ]
  [ "$output" = "hello" ]
}

@test "_run_command: --quiet suppresses error output on missing program" {
  run -127 _run_command --quiet --soft -- __nonexistent_prog_xyz__
  [ -z "$output" ]
}

@test "_run_command: --interactive-sudo flag is accepted without error" {
  function sudo() { "$@"; }
  export -f sudo
  run _run_command --interactive-sudo --soft -- echo hi
  [ "$status" -eq 0 ]
  [ "$output" = "hi" ]
  unset -f sudo
}

@test "_run_command: --prefer-sudo flag is accepted without error" {
  function sudo() { "$@"; }
  export -f sudo
  run _run_command --prefer-sudo --soft -- echo hi
  [ "$status" -eq 0 ]
  [ "$output" = "hi" ]
  unset -f sudo
}

@test "_run_command_handle_failure: soft mode returns rc without exiting" {
  run _run_command_handle_failure "myprog" 42 0 1 myprog arg1
  [ "$status" -eq 42 ]
}

@test "_run_command_handle_failure: quiet=1 suppresses output" {
  run _run_command_handle_failure "myprog" 1 1 1 myprog arg1
  [ -z "$output" ]
  [ "$status" -eq 1 ]
}

@test "_node_install_via_redhat: returns 1 when no redhat package manager present" {
  _command_exist() { return 1; }
  export -f _command_exist

  run _node_install_via_redhat
  [ "$status" -eq 1 ]
  unset -f _command_exist
}

@test "_ensure_antigravity_ide: no-op when antigravity already installed" {
  _command_exist() { [[ "$1" == antigravity ]]; }
  export -f _command_exist

  run _ensure_antigravity_ide
  [ "$status" -eq 0 ]
  unset -f _command_exist
}

@test "_ensure_antigravity_ide: installs via brew on macOS" {
  installed=0
  _command_exist() {
    case "$1" in
      antigravity) [[ "$installed" -eq 1 ]] ;;
      brew) return 0 ;;
      *) return 1 ;;
    esac
  }
  _is_mac() { return 0; }
  _run_command() {
    if [[ "$*" == *"brew install --cask antigravity"* ]]; then
      installed=1
    fi
    return 0
  }
  export -f _command_exist _is_mac _run_command

  run _ensure_antigravity_ide
  [ "$status" -eq 0 ]
  unset -f _command_exist _is_mac _run_command
}

@test "_ensure_antigravity_ide: installs via apt-get on Debian" {
  installed=0
  _command_exist() {
    case "$1" in
      antigravity) [[ "$installed" -eq 1 ]] ;;
      apt-get) return 0 ;;
      *) return 1 ;;
    esac
  }
  _is_mac() { return 1; }
  _is_debian_family() { return 0; }
  _is_redhat_family() { return 1; }
  _sudo_available() { return 0; }
  _run_command() {
    if [[ "$*" == *"apt-get install"*"antigravity"* ]]; then
      installed=1
    fi
    return 0
  }
  export -f _command_exist _is_mac _is_debian_family _is_redhat_family _sudo_available _run_command

  run _ensure_antigravity_ide
  [ "$status" -eq 0 ]
  unset -f _command_exist _is_mac _is_debian_family _is_redhat_family _sudo_available _run_command
}

@test "_ensure_antigravity_mcp_playwright: no-op when playwright entry already present" {
  config_file="$(mktemp -t ag-mcp-test.XXXXXX)"
  printf '{"mcpServers":{"playwright":{"command":"npx","args":["-y","@playwright/mcp@0.0.26"]}}}\n' > "$config_file"

  _antigravity_mcp_config_path() { printf '%s\n' "$config_file"; }
  _command_exist() { [[ "$1" == jq ]]; }
  export -f _antigravity_mcp_config_path _command_exist

  run _ensure_antigravity_mcp_playwright
  [ "$status" -eq 0 ]

  rm -f "$config_file"
  unset -f _antigravity_mcp_config_path _command_exist
}

@test "_ensure_antigravity_mcp_playwright: injects playwright entry into empty config" {
  config_dir="$(mktemp -d -t ag-mcp-dir.XXXXXX)"
  config_file="${config_dir}/mcp_config.json"

  _antigravity_mcp_config_path() { printf '%s\n' "$config_file"; }
  _command_exist() { [[ "$1" == jq ]]; }
  export -f _antigravity_mcp_config_path _command_exist

  run _ensure_antigravity_mcp_playwright
  [ "$status" -eq 0 ]
  grep -q '"playwright"' "$config_file"

  rm -rf "$config_dir"
  unset -f _antigravity_mcp_config_path _command_exist
}

@test "_antigravity_browser_ready: returns 0 when port 9222 responds" {
  _command_exist() { [[ "$1" == curl ]]; }
  _run_command() { return 0; }
  export -f _command_exist _run_command

  run _antigravity_browser_ready 4
  [ "$status" -eq 0 ]
  unset -f _command_exist _run_command
}

@test "_antigravity_browser_ready: errors when port never responds within timeout" {
  _command_exist() { [[ "$1" == curl ]]; }
  _run_command() { return 1; }
  _err() { echo "ERROR: $*" >&2; return 1; }
  export -f _command_exist _run_command _err

  run _antigravity_browser_ready 2
  [ "$status" -ne 0 ]
  unset -f _command_exist _run_command _err
}
