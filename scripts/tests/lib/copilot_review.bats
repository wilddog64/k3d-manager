#!/usr/bin/env bats
# shellcheck shell=bash disable=SC1091,SC2329

bats_require_minimum_version 1.5.0

setup() {
  SYSTEM_LIB="${BATS_TEST_DIRNAME}/../../lib/system.sh"
  # shellcheck source=/dev/null
  source "$SYSTEM_LIB"

  _safe_path()          { return 0; }
  _ensure_copilot_cli() { return 0; }
  _k3dm_repo_root()     { printf '%s\n' "$BATS_TEST_TMPDIR"; }
  _copilot_scope_prompt() { printf '%s\n' "$1"; }
  _copilot_prompt_guard() { return 0; }
  export -f _safe_path _ensure_copilot_cli _k3dm_repo_root \
    _copilot_scope_prompt _copilot_prompt_guard

  : > "$BATS_TEST_TMPDIR/run_command.log"
  _run_command() {
    printf '%s\n' "$@" >> "$BATS_TEST_TMPDIR/run_command.log"
    return 0
  }
  export -f _run_command
}

@test "_copilot_review passes --allow-all-tools to copilot CLI" {
  run _copilot_review --prompt "review this"
  [ "$status" -eq 0 ]
  grep -q -- "--allow-all-tools" "$BATS_TEST_TMPDIR/run_command.log"
}

@test "_copilot_review deny-tool patterns are well-formed with closing paren" {
  run _copilot_review --prompt "review this"
  [ "$status" -eq 0 ]
  grep -q "shell(sudo)"  "$BATS_TEST_TMPDIR/run_command.log"
  grep -q "shell(eval)"  "$BATS_TEST_TMPDIR/run_command.log"
  grep -q "shell(curl)"  "$BATS_TEST_TMPDIR/run_command.log"
  grep -q "shell(wget)"  "$BATS_TEST_TMPDIR/run_command.log"
}
