#!/usr/bin/env bats
# shellcheck shell=bash

setup() {
  REPO_ROOT="$(cd -P "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  LOCAL_LIB="${REPO_ROOT}/scripts/lib/system.sh"
  FOUNDATION_LIB="${REPO_ROOT}/scripts/lib/foundation/scripts/lib/system.sh"
}

@test "system.sh shim: _run_command_resolve_sudo is the lib-foundation definition" {
  run bash -c 'source "$1" >/dev/null 2>&1; declare -f _run_command_resolve_sudo' _ "$LOCAL_LIB"
  [ "$status" -eq 0 ]
  local_def="$output"
  run bash -c 'source "$1" >/dev/null 2>&1; declare -f _run_command_resolve_sudo' _ "$FOUNDATION_LIB"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ "$local_def" = "$output" ]
}

@test "system.sh shim: no-TTY interactive sudo resolves to sudo -n and the system binary" {
  run bash -c 'source "$1" >/dev/null 2>&1; _run_command_resolve_sudo install 1 0 1 </dev/null; printf "%s|" "${_RCRS_RUNNER[@]}"' _ "$LOCAL_LIB"
  [ "$status" -eq 0 ]
  [ "$output" = "sudo|-n|/usr/bin/install|" ]
}

@test "system.sh shim: defines only the k3d-manager kubeconform helpers itself" {
  run bash -c 'grep -oE "^(function[[:space:]]+)?_?[A-Za-z0-9_]+[[:space:]]*\(\)" "$1" | sed -E "s/^function[[:space:]]+//; s/[[:space:]]*\(\)//" | sort | tr "\n" " "' _ "$LOCAL_LIB"
  [ "$status" -eq 0 ]
  [ "$output" = "_ensure_kubeconform _install_kubeconform_from_release _kubeconform_sha256 " ]
}

@test "system.sh shim: SCRIPT_DIR defaults to the k3d-manager scripts dir" {
  run bash -c 'unset SCRIPT_DIR; source "$1" >/dev/null 2>&1; printf "%s" "$SCRIPT_DIR"' _ "$LOCAL_LIB"
  [ "$status" -eq 0 ]
  [ "$output" = "${REPO_ROOT}/scripts" ]
}

@test "system.sh shim: loads with no external commands on PATH" {
  run bash -c 'PATH=/dev/null; source "$1" >/dev/null 2>&1; declare -F _run_command >/dev/null && declare -F _ensure_kubeconform >/dev/null && [ "$KUBECONFORM_VERSION" = "0.7.0" ]' _ "$LOCAL_LIB"
  [ "$status" -eq 0 ]
}
