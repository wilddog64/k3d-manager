#!/usr/bin/env bats
# shellcheck shell=bash

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
