#!/usr/bin/env bats
# scripts/tests/lib/acg.bats — unit tests for acg.sh credential helpers

setup() {
  _info() { :; }
  _run_command() { shift; "$@"; }
  _ensure_antigravity() { :; }
  _ensure_antigravity_ide() { :; }
  _ensure_antigravity_mcp_playwright() { :; }
  _antigravity_launch() { :; }
  _antigravity_ensure_acg_session() { :; }
  _antigravity_gemini_prompt() { :; }
  export -f _info _run_command _ensure_antigravity _ensure_antigravity_ide
  export -f _ensure_antigravity_mcp_playwright _antigravity_launch
  export -f _antigravity_ensure_acg_session _antigravity_gemini_prompt

  export HOME="${BATS_TEST_TMPDIR}"
  source "scripts/plugins/acg.sh"
}

# _acg_write_credentials

@test "_acg_write_credentials writes [default] profile to ~/.aws/credentials" {
  _acg_write_credentials "AKIAIOSFODNN7EXAMPLE" "wJalrXUtnFEMI/K7MDENG" "AQoDYXdzEJr"
  run cat "${HOME}/.aws/credentials"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[default]"* ]]
  [[ "$output" == *"aws_access_key_id=AKIAIOSFODNN7EXAMPLE"* ]]
  [[ "$output" == *"aws_secret_access_key=wJalrXUtnFEMI/K7MDENG"* ]]
  [[ "$output" == *"aws_session_token=AQoDYXdzEJr"* ]]
}

@test "_acg_write_credentials sets file permissions to 600" {
  _acg_write_credentials "AKID" "SECRET" "TOKEN"
  run bash -c "stat -c '%a' \"${HOME}/.aws/credentials\" 2>/dev/null || stat -f '%A' \"${HOME}/.aws/credentials\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"600"* ]]
}

@test "_acg_write_credentials creates ~/.aws directory if missing" {
  rm -rf "${HOME}/.aws"
  _acg_write_credentials "AKID" "SECRET" "TOKEN"
  [ -f "${HOME}/.aws/credentials" ]
}

# acg_import_credentials

@test "acg_import_credentials parses label format (Pluralsight UI copy)" {
  local input="AWS Access Key ID: AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key: wJalrXUtnFEMI/K7MDENG
AWS Session Token: AQoDYXdzEJr"
  run bash -c "source scripts/plugins/acg.sh && printf '%s' '$input' | acg_import_credentials"
  [ "$status" -eq 0 ]
  run cat "${HOME}/.aws/credentials"
  [[ "$output" == *"aws_access_key_id=AKIAIOSFODNN7EXAMPLE"* ]]
}

@test "acg_import_credentials parses export format" {
  local input="export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
export AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG
export AWS_SESSION_TOKEN=AQoDYXdzEJr"
  run bash -c "source scripts/plugins/acg.sh && printf '%s' '$input' | acg_import_credentials"
  [ "$status" -eq 0 ]
  run cat "${HOME}/.aws/credentials"
  [[ "$output" == *"aws_access_key_id=AKIAIOSFODNN7EXAMPLE"* ]]
}

@test "acg_import_credentials returns 1 on empty/unparseable input" {
  run bash -c "source scripts/plugins/acg.sh && printf '' | acg_import_credentials"
  [ "$status" -eq 1 ]
}

@test "acg_import_credentials --help exits 0" {
  run acg_import_credentials --help
  [ "$status" -eq 0 ]
}

@test "acg_get_credentials --help exits 0" {
  run acg_get_credentials --help
  [ "$status" -eq 0 ]
}
