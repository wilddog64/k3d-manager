#!/usr/bin/env bats
# scripts/tests/plugins/aws.bats — unit tests for aws.sh credential helpers

setup() {
  _info() { :; }
  _write_sensitive_file() {
    local path="$1" data="$2"
    mkdir -p "$(dirname "$path")"
    printf '%s' "$data" > "$path"
    chmod 600 "$path"
  }
  _ensure_antigravity() { :; }
  _ensure_antigravity_ide() { :; }
  _ensure_antigravity_mcp_playwright() { :; }
  _antigravity_launch() { :; }
  _antigravity_ensure_acg_session() { :; }
  _antigravity_gemini_prompt() { :; }
  export -f _info _write_sensitive_file
  export -f _ensure_antigravity _ensure_antigravity_ide
  export -f _ensure_antigravity_mcp_playwright _antigravity_launch
  export -f _antigravity_ensure_acg_session _antigravity_gemini_prompt

  export HOME="${BATS_TEST_TMPDIR}"
  source "scripts/plugins/aws.sh"
}

# aws_import_credentials — CSV format

@test "aws_import_credentials parses simple CSV (Access key ID,Secret access key)" {
  local input="Access key ID,Secret access key
AKIAIOSFODNN7EXAMPLE,wJalrXUtnFEMI/K7MDENG"
  run bash -c "
    _info(){ :; }
    _write_sensitive_file(){ local p=\$1 d=\$2; mkdir -p \"\$(dirname \"\$p\")\"; printf '%s' \"\$d\" > \"\$p\"; chmod 600 \"\$p\"; }
    _ensure_antigravity(){ :; }; _ensure_antigravity_ide(){ :; }
    _ensure_antigravity_mcp_playwright(){ :; }; _antigravity_launch(){ :; }
    _antigravity_ensure_acg_session(){ :; }; _antigravity_gemini_prompt(){ :; }
    export -f _info _write_sensitive_file _ensure_antigravity _ensure_antigravity_ide
    export -f _ensure_antigravity_mcp_playwright _antigravity_launch
    export -f _antigravity_ensure_acg_session _antigravity_gemini_prompt
    export HOME='${BATS_TEST_TMPDIR}'
    source scripts/plugins/aws.sh
    printf '%s' \"${input}\" | aws_import_credentials"
  [ "$status" -eq 0 ]
  run cat "${BATS_TEST_TMPDIR}/.aws/credentials"
  [[ "$output" == *"aws_access_key_id=AKIAIOSFODNN7EXAMPLE"* ]]
  [[ "$output" == *"aws_secret_access_key=wJalrXUtnFEMI/K7MDENG"* ]]
}

@test "aws_import_credentials parses CSV with User name column" {
  local input="User name,Access key ID,Secret access key
alice,AKIAIOSFODNN7EXAMPLE,wJalrXUtnFEMI/K7MDENG"
  run bash -c "
    _info(){ :; }
    _write_sensitive_file(){ local p=\$1 d=\$2; mkdir -p \"\$(dirname \"\$p\")\"; printf '%s' \"\$d\" > \"\$p\"; chmod 600 \"\$p\"; }
    _ensure_antigravity(){ :; }; _ensure_antigravity_ide(){ :; }
    _ensure_antigravity_mcp_playwright(){ :; }; _antigravity_launch(){ :; }
    _antigravity_ensure_acg_session(){ :; }; _antigravity_gemini_prompt(){ :; }
    export -f _info _write_sensitive_file _ensure_antigravity _ensure_antigravity_ide
    export -f _ensure_antigravity_mcp_playwright _antigravity_launch
    export -f _antigravity_ensure_acg_session _antigravity_gemini_prompt
    export HOME='${BATS_TEST_TMPDIR}'
    source scripts/plugins/aws.sh
    printf '%s' \"${input}\" | aws_import_credentials"
  [ "$status" -eq 0 ]
  run cat "${BATS_TEST_TMPDIR}/.aws/credentials"
  [[ "$output" == *"aws_access_key_id=AKIAIOSFODNN7EXAMPLE"* ]]
  [[ "$output" == *"aws_secret_access_key=wJalrXUtnFEMI/K7MDENG"* ]]
}

# aws_import_credentials — quoted export format

@test "aws_import_credentials parses quoted export values" {
  run bash -c "
    _info(){ :; }
    _write_sensitive_file(){ local p=\$1 d=\$2; mkdir -p \"\$(dirname \"\$p\")\"; printf '%s' \"\$d\" > \"\$p\"; chmod 600 \"\$p\"; }
    _ensure_antigravity(){ :; }; _ensure_antigravity_ide(){ :; }
    _ensure_antigravity_mcp_playwright(){ :; }; _antigravity_launch(){ :; }
    _antigravity_ensure_acg_session(){ :; }; _antigravity_gemini_prompt(){ :; }
    export -f _info _write_sensitive_file _ensure_antigravity _ensure_antigravity_ide
    export -f _ensure_antigravity_mcp_playwright _antigravity_launch
    export -f _antigravity_ensure_acg_session _antigravity_gemini_prompt
    export HOME='${BATS_TEST_TMPDIR}'
    source scripts/plugins/aws.sh
    printf '%s\n%s\n%s\n' \
      'export AWS_ACCESS_KEY_ID=\"AKIAIOSFODNN7EXAMPLE\"' \
      'export AWS_SECRET_ACCESS_KEY=\"wJalrXUtnFEMI/K7MDENG\"' \
      'export AWS_SESSION_TOKEN=\"AQoDYXdzEJr\"' | aws_import_credentials"
  [ "$status" -eq 0 ]
  run cat "${BATS_TEST_TMPDIR}/.aws/credentials"
  [[ "$output" == *"aws_access_key_id=AKIAIOSFODNN7EXAMPLE"* ]]
  [[ "$output" == *"aws_secret_access_key=wJalrXUtnFEMI/K7MDENG"* ]]
  [[ "$output" == *"aws_session_token=AQoDYXdzEJr"* ]]
}

# aws_import_credentials — error cases

@test "aws_import_credentials returns 1 on unparseable input" {
  run bash -c "
    _info(){ :; }
    _write_sensitive_file(){ :; }
    _ensure_antigravity(){ :; }; _ensure_antigravity_ide(){ :; }
    _ensure_antigravity_mcp_playwright(){ :; }; _antigravity_launch(){ :; }
    _antigravity_ensure_acg_session(){ :; }; _antigravity_gemini_prompt(){ :; }
    export -f _info _write_sensitive_file _ensure_antigravity _ensure_antigravity_ide
    export -f _ensure_antigravity_mcp_playwright _antigravity_launch
    export -f _antigravity_ensure_acg_session _antigravity_gemini_prompt
    export HOME='${BATS_TEST_TMPDIR}'
    source scripts/plugins/aws.sh
    printf '' | aws_import_credentials"
  [ "$status" -eq 1 ]
}

@test "aws_import_credentials --help exits 0" {
  run aws_import_credentials --help
  [ "$status" -eq 0 ]
}
