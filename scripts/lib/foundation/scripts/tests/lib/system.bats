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
}

@test "_node_install_via_redhat: returns 1 when no redhat package manager present" {
  _command_exist() { return 1; }
  export -f _command_exist

  run _node_install_via_redhat
  [ "$status" -eq 1 ]
  unset -f _command_exist
}
